-- =================================================================
--  CAJA: apertura, cierre y arqueo
--  - Una sola caja abierta a la vez (para todo el negocio).
--  - Apertura con monto inicial (mínimo Gs. 20.000).
--  - Cierre con el conteo de billetes y monedas (obligatorio). El efectivo
--    y las transferencias vendidas los calcula el servidor (no se tipean).
--  - Queda quién abrió y quién cerró, con fecha y hora.
--  - Retiros de dinero, en efectivo o por transferencia, con quién recibe
--    (obligatorio) y descripción. En efectivo, entre todos no pueden pasar el
--    monto de apertura; por transferencia, no más de lo que entró por transferencia.
--    Se descuentan de lo que debería haber en cada uno.
--  - Las operaciones van por funciones (con clave contra duplicados);
--    la tabla no se escribe directo.
-- =================================================================

create table if not exists public.cash_sessions (
  id uuid primary key default gen_random_uuid(),
  number bigint generated always as identity unique,
  status text not null default 'abierta' check (status in ('abierta', 'cerrada')),

  opened_by uuid not null,
  opened_by_name text not null,
  opened_by_username text,
  opened_by_role text not null,
  opened_at timestamptz not null default now(),
  opening_amount integer not null check (opening_amount >= 20000 and opening_amount <= 999999999),
  open_key uuid not null unique,

  closed_by uuid,
  closed_by_name text,
  closed_by_username text,
  closed_at timestamptz,
  close_key uuid unique,

  -- Foto del cierre (calculado por el servidor en ese momento).
  sales_count integer,
  cash_sales integer,
  transfer_sales integer,
  withdrawals_total integer,
  withdrawals_cash integer,
  withdrawals_transfer integer,
  expected_cash integer,
  expected_transfer integer,
  -- Conteo: {"100000": 3, "50000": 1, ...} (cantidad de cada billete / moneda).
  denominations jsonb,
  counted_cash integer,
  difference integer,

  check (status = 'abierta' or (closed_at is not null and denominations is not null and counted_cash is not null))
);

-- Una sola caja abierta a la vez.
create unique index if not exists cash_sessions_una_abierta on public.cash_sessions ((true)) where status = 'abierta';
create index if not exists cash_sessions_opened_at on public.cash_sessions (opened_at desc);

create table if not exists public.cash_withdrawals (
  id uuid primary key default gen_random_uuid(),
  number bigint generated always as identity unique,
  cash_session_id uuid not null references public.cash_sessions (id),
  amount integer not null check (amount > 0 and amount <= 999999999),
  method text not null default 'efectivo' check (method in ('efectivo', 'transferencia')),
  received_by_name text not null check (public.texto_ok(received_by_name, 80, 3)),
  description text check (description is null or public.texto_largo_ok(description, 200)),
  -- Quién entregó el dinero: el que abrió la caja.
  given_by_name text not null,
  created_by uuid not null,
  created_by_name text not null,
  created_at timestamptz not null default now(),
  idempotency_key uuid not null unique
);
create index if not exists cash_withdrawals_caja on public.cash_withdrawals (cash_session_id);
alter table public.cash_withdrawals enable row level security;
create policy admins_read on public.cash_withdrawals for select to authenticated using ((select public.is_admin()));
revoke insert, update, delete on public.cash_withdrawals from authenticated, anon;

alter table public.cash_sessions enable row level security;
-- La lista (con montos) la ve el administrador; el vendedor usa resumen_caja().
create policy admins_read on public.cash_sessions for select to authenticated using ((select public.is_admin()));
revoke insert, update, delete on public.cash_sessions from authenticated, anon;

-- Billetes y monedas que se cuentan.
create or replace function public.denominaciones_caja() returns integer[]
language sql immutable set search_path to '' as $$
  select array[100000, 50000, 20000, 10000, 5000, 2000, 1000, 500, 100, 50];
$$;

-- Totales de una caja: lo vendido desde que se abrió (ventas activas, sin lo devuelto).
create or replace function public.totales_caja(p_desde timestamptz, p_hasta timestamptz)
returns table (ventas integer, efectivo integer, transferencia integer)
language sql stable security definer set search_path to '' as $$
  select count(*)::int,
         coalesce(sum(case when total > 0 then round(paid_cash::numeric * (total - returned_amount) / total) else 0 end), 0)::int,
         coalesce(sum(case when total > 0 then round(paid_transfer::numeric * (total - returned_amount) / total) else 0 end), 0)::int
  from public.sales
  where status = 'activa' and created_at >= p_desde and created_at <= p_hasta;
$$;
revoke all on function public.totales_caja(timestamptz, timestamptz) from public, anon, authenticated;

-- Retiros de una caja (lista para pantallas y comprobantes).
create or replace function public.retiros_caja_json(p_caja uuid) returns jsonb
language sql stable security definer set search_path to '' as $$
  select coalesce(jsonb_agg(to_jsonb(w) order by w.created_at), '[]'::jsonb)
  from public.cash_withdrawals w where w.cash_session_id = p_caja;
$$;
revoke all on function public.retiros_caja_json(uuid) from public, anon, authenticated;

create or replace function public.total_retiros_caja(p_caja uuid, p_metodo text default null) returns integer
language sql stable security definer set search_path to '' as $$
  select coalesce(sum(amount), 0)::int from public.cash_withdrawals
  where cash_session_id = p_caja and (p_metodo is null or method = p_metodo);
$$;
revoke all on function public.total_retiros_caja(uuid, text) from public, anon, authenticated;

-- ---------- Abrir caja ----------
create or replace function public.abrir_caja(p_monto integer, p_idempotency_key uuid)
returns public.cash_sessions
language plpgsql security definer set search_path to '' as $$
declare
  v public.cash_sessions%rowtype;
  m public.app_members%rowtype;
begin
  perform public.assert_can_write();
  perform public.idem_lock('caja_abrir', p_idempotency_key);

  -- Reintento de la misma apertura: se devuelve la que ya se hizo.
  select * into v from public.cash_sessions where open_key = p_idempotency_key;
  if found then return v; end if;

  if p_monto is null or p_monto < 20000 then
    raise exception 'El monto inicial mínimo es Gs. 20.000.' using errcode = 'P0001';
  end if;
  if p_monto > 999999999 then
    raise exception 'Revisá el monto inicial: es demasiado grande.' using errcode = 'P0001';
  end if;

  select * into v from public.cash_sessions where status = 'abierta';
  if found then
    raise exception 'Ya hay una caja abierta (desde las % por %). Cerrala antes de abrir otra.',
      to_char(v.opened_at at time zone 'America/Asuncion', 'HH24:MI'), v.opened_by_name using errcode = 'P0001';
  end if;

  select * into m from public.app_members where user_id = (select auth.uid());
  insert into public.cash_sessions (opened_by, opened_by_name, opened_by_username, opened_by_role, opening_amount, open_key)
  values ((select auth.uid()), coalesce(m.full_name, 'Sin nombre'), m.username, m.role, p_monto, p_idempotency_key)
  returning * into v;
  return v;
end;
$$;
revoke all on function public.abrir_caja(integer, uuid) from public, anon;
grant execute on function public.abrir_caja(integer, uuid) to authenticated;

-- ---------- Caja abierta y sus totales al momento ----------
create or replace function public.resumen_caja() returns jsonb
language plpgsql stable security definer set search_path to '' as $$
declare
  v public.cash_sessions%rowtype;
  t record;
begin
  if not public.is_member() then
    raise exception 'No tenés permiso para ver la caja.' using errcode = '42501';
  end if;
  select * into v from public.cash_sessions where status = 'abierta';
  if not found then return null; end if;
  select * into t from public.totales_caja(v.opened_at, now());
  return to_jsonb(v) || jsonb_build_object(
    'sales_count', t.ventas,
    'cash_sales', t.efectivo,
    'transfer_sales', t.transferencia,
    'withdrawals_total', public.total_retiros_caja(v.id),
    'withdrawals_cash', public.total_retiros_caja(v.id, 'efectivo'),
    'withdrawals_transfer', public.total_retiros_caja(v.id, 'transferencia'),
    'expected_cash', v.opening_amount + t.efectivo - public.total_retiros_caja(v.id, 'efectivo'),
    'expected_transfer', t.transferencia - public.total_retiros_caja(v.id, 'transferencia'),
    'withdrawals', public.retiros_caja_json(v.id));
end;
$$;
revoke all on function public.resumen_caja() from public, anon;
grant execute on function public.resumen_caja() to authenticated;

-- ---------- Cerrar caja con el conteo ----------
create or replace function public.cerrar_caja(p_caja uuid, p_conteo jsonb, p_idempotency_key uuid)
returns jsonb
language plpgsql security definer set search_path to '' as $$
declare
  v public.cash_sessions%rowtype;
  m public.app_members%rowtype;
  t record;
  d integer;
  cant numeric;
  contado bigint := 0;
  conteo jsonb := '{}'::jsonb;
begin
  perform public.assert_can_write();
  perform public.idem_lock('caja_cerrar', p_idempotency_key);

  select * into v from public.cash_sessions where id = p_caja for update;
  if not found then
    raise exception 'La caja no existe.' using errcode = 'P0001';
  end if;
  if v.status = 'cerrada' then
    -- Reintento del mismo cierre: se devuelve el cierre ya hecho.
    if v.close_key = p_idempotency_key then
      return to_jsonb(v) || jsonb_build_object('withdrawals', public.retiros_caja_json(v.id));
    end if;
    raise exception 'Esta caja ya se cerró a las % por %.',
      to_char(v.closed_at at time zone 'America/Asuncion', 'HH24:MI'), v.closed_by_name using errcode = 'P0001';
  end if;

  -- El conteo es obligatorio: cada billete y moneda, número entero de 0 a 100.000.
  if p_conteo is null or jsonb_typeof(p_conteo) <> 'object' then
    raise exception 'Falta el conteo de billetes y monedas.' using errcode = 'P0001';
  end if;
  foreach d in array public.denominaciones_caja() loop
    if not (p_conteo ? d::text) or jsonb_typeof(p_conteo -> d::text) <> 'number' then
      raise exception 'Falta la cantidad de %. Si no hay, poné 0.',
        case when d >= 2000 then 'billetes de Gs. ' else 'monedas de Gs. ' end || replace(to_char(d, 'FM999,999'), ',', '.') using errcode = 'P0001';
    end if;
    cant := (p_conteo ->> d::text)::numeric;
    if cant < 0 or cant > 100000 or cant <> trunc(cant) then
      raise exception 'Revisá la cantidad de Gs. %: tiene que ser un número entero.', replace(to_char(d, 'FM999,999'), ',', '.') using errcode = 'P0001';
    end if;
    conteo := conteo || jsonb_build_object(d::text, cant::int);
    contado := contado + cant::bigint * d;
  end loop;
  if contado > 999999999 then
    raise exception 'El total contado es demasiado grande. Revisá las cantidades.' using errcode = 'P0001';
  end if;

  select * into m from public.app_members where user_id = (select auth.uid());
  select * into t from public.totales_caja(v.opened_at, now());

  update public.cash_sessions set
    status = 'cerrada',
    closed_by = (select auth.uid()),
    closed_by_name = coalesce(m.full_name, 'Sin nombre'),
    closed_by_username = m.username,
    closed_at = now(),
    close_key = p_idempotency_key,
    sales_count = t.ventas,
    cash_sales = t.efectivo,
    transfer_sales = t.transferencia,
    withdrawals_total = public.total_retiros_caja(v.id),
    withdrawals_cash = public.total_retiros_caja(v.id, 'efectivo'),
    withdrawals_transfer = public.total_retiros_caja(v.id, 'transferencia'),
    expected_cash = v.opening_amount + t.efectivo - public.total_retiros_caja(v.id, 'efectivo'),
    expected_transfer = t.transferencia - public.total_retiros_caja(v.id, 'transferencia'),
    denominations = conteo,
    counted_cash = contado::int,
    difference = contado::int - (v.opening_amount + t.efectivo - public.total_retiros_caja(v.id, 'efectivo'))
  where id = v.id
  returning * into v;
  return to_jsonb(v) || jsonb_build_object('withdrawals', public.retiros_caja_json(v.id));
end;
$$;
revoke all on function public.cerrar_caja(uuid, jsonb, uuid) from public, anon;
grant execute on function public.cerrar_caja(uuid, jsonb, uuid) to authenticated;

-- ---------- Retiro de dinero ----------
-- Entre todos los retiros no se puede sacar más que el monto de apertura.
create or replace function public.retirar_caja(
  p_caja uuid, p_monto integer, p_metodo text, p_recibe text, p_descripcion text, p_idempotency_key uuid
) returns jsonb
language plpgsql security definer set search_path to '' as $$
declare
  v public.cash_sessions%rowtype;
  w public.cash_withdrawals%rowtype;
  m public.app_members%rowtype;
  ya integer;
  tope integer;
  t record;
  recibe text := nullif(regexp_replace(trim(coalesce(p_recibe, '')), '\s+', ' ', 'g'), '');
  descr text := nullif(trim(coalesce(p_descripcion, '')), '');
begin
  perform public.assert_can_write();
  perform public.idem_lock('caja_retiro', p_idempotency_key);

  select * into w from public.cash_withdrawals where idempotency_key = p_idempotency_key;
  if found then
    return to_jsonb(w) || jsonb_build_object('caja_number', (select number from public.cash_sessions where id = w.cash_session_id));
  end if;

  select * into v from public.cash_sessions where id = p_caja for update;
  if not found or v.status <> 'abierta' then
    raise exception 'La caja no está abierta.' using errcode = 'P0001';
  end if;
  if recibe is null or length(recibe) < 3 then
    raise exception 'Escribí el nombre de quien recibe el dinero.' using errcode = 'P0001';
  end if;
  if recibe !~ '^[A-Za-zÁÉÍÓÚÜÑáéíóúüñ'' .-]+$' then
    raise exception 'El nombre de quien recibe solo puede tener letras.' using errcode = 'P0001';
  end if;
  if p_metodo is null or p_metodo not in ('efectivo', 'transferencia') then
    raise exception 'Elegí si el retiro es en efectivo o por transferencia.' using errcode = 'P0001';
  end if;
  if p_monto is null or p_monto <= 0 then
    raise exception 'Escribí el monto a retirar.' using errcode = 'P0001';
  end if;
  ya := public.total_retiros_caja(v.id, p_metodo);
  if p_metodo = 'efectivo' then
    -- En efectivo: entre todos, no más que el monto de apertura.
    tope := v.opening_amount;
  else
    -- Por transferencia: no más de lo que entró por transferencia.
    select * into t from public.totales_caja(v.opened_at, now());
    tope := t.transferencia;
  end if;
  if ya + p_monto > tope then
    raise exception 'No se puede retirar tanto %: el máximo es % (ya se retiró %, queda %).',
      case when p_metodo = 'efectivo' then 'en efectivo' else 'por transferencia' end,
      'Gs. ' || replace(to_char(tope, 'FM999,999,999'), ',', '.'),
      'Gs. ' || replace(to_char(ya, 'FM999,999,999'), ',', '.'),
      'Gs. ' || replace(to_char(greatest(tope - ya, 0), 'FM999,999,999'), ',', '.') using errcode = 'P0001';
  end if;

  select * into m from public.app_members where user_id = (select auth.uid());
  insert into public.cash_withdrawals (cash_session_id, amount, method, received_by_name, description, given_by_name,
                                       created_by, created_by_name, idempotency_key)
  values (v.id, p_monto, p_metodo, recibe, descr, v.opened_by_name, (select auth.uid()), coalesce(m.full_name, 'Sin nombre'), p_idempotency_key)
  returning * into w;
  return to_jsonb(w) || jsonb_build_object('caja_number', v.number);
end;
$$;
revoke all on function public.retirar_caja(uuid, integer, text, text, text, uuid) from public, anon;
grant execute on function public.retirar_caja(uuid, integer, text, text, text, uuid) to authenticated;

-- ---------- Una caja (para reimprimir el comprobante) ----------
-- El administrador ve cualquiera; el vendedor, solo las que abrió o cerró él.
create or replace function public.caja(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path to '' as $$
declare v public.cash_sessions%rowtype;
begin
  select * into v from public.cash_sessions where id = p_id;
  if not found or not (public.is_admin() or v.opened_by = (select auth.uid()) or v.closed_by = (select auth.uid())) then
    raise exception 'No se encontró esa caja.' using errcode = 'P0001';
  end if;
  return to_jsonb(v) || jsonb_build_object('withdrawals', public.retiros_caja_json(v.id));
end;
$$;
revoke all on function public.caja(uuid) from public, anon;
grant execute on function public.caja(uuid) to authenticated;

-- ---------- Sin caja abierta no se vende ----------
do $$
declare f regprocedure; d text;
begin
  foreach f in array array[
    'public.create_sale(jsonb,text,uuid,integer,text,uuid,uuid,integer,integer,integer)'::regprocedure,
    'public.create_sale(jsonb,text,uuid,integer,text,uuid,uuid)'::regprocedure
  ] loop
    d := pg_get_functiondef(f);
    if position('cash_sessions' in d) > 0 then continue; end if;
    if position('  if p_items is null or jsonb_typeof(p_items)' in d) = 0 then
      raise exception 'No se encontró dónde agregar el control de caja en %', f;
    end if;
    -- Se controla después de la clave (un reintento de una venta ya hecha se devuelve igual).
    d := replace(d, '  if p_items is null or jsonb_typeof(p_items)',
      '  if not exists (select 1 from public.cash_sessions where status = ''abierta'') then' || chr(10) ||
      '    raise exception ''La caja está cerrada. Abrila para poder vender.'' using errcode = ''P0001'';' || chr(10) ||
      '  end if;' || chr(10) ||
      '  if p_items is null or jsonb_typeof(p_items)');
    execute d;
  end loop;
end $$;
