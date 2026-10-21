-- =================================================================
--  GASTOS DEL NEGOCIO
-- =================================================================
create or replace function public.categorias_gasto() returns text[]
language sql immutable set search_path to '' as $$
  select array[
    'Alquiler', 'Sueldos', 'Pago a empleados', 'Flete', 'Luz (ANDE)', 'Agua', 'Internet y teléfono',
    'Combustible', 'Repuestos y reparaciones', 'Mantenimiento del local', 'Impuestos', 'Limpieza',
    'Útiles de oficina', 'Publicidad', 'Comida y bebida', 'Otros'
  ];
$$;
grant execute on function public.categorias_gasto() to authenticated;

create table if not exists public.expenses (
  id uuid primary key default gen_random_uuid(),
  number bigint generated always as identity unique,
  category text not null,
  amount integer not null check (amount > 0 and amount <= 999999999),
  description text check (description is null or public.texto_largo_ok(description, 200)),
  invoice_number text check (invoice_number is null or invoice_number ~ '^[0-9A-Za-z-]{1,30}$'),
  -- Día y hora en que se hizo el gasto (puede ser anterior a cuando se carga).
  spent_at timestamptz not null default now(),
  status text not null default 'activo' check (status in ('activo', 'anulado')),
  void_reason text,
  voided_at timestamptz,
  created_by uuid not null default auth.uid(),
  created_by_name text,
  created_at timestamptz not null default now(),
  idempotency_key uuid not null unique
);
create index if not exists expenses_spent_at on public.expenses (spent_at desc);
alter table public.expenses enable row level security;
create policy admins_read on public.expenses for select to authenticated using ((select public.is_admin()));
revoke insert, update, delete on public.expenses from authenticated, anon;

-- Registrar un gasto (solo el administrador; con clave contra duplicados).
create or replace function public.registrar_gasto(
  p_categoria text, p_monto integer, p_descripcion text, p_factura text, p_fecha timestamptz, p_idempotency_key uuid
) returns public.expenses
language plpgsql security definer set search_path to '' as $$
declare
  v public.expenses%rowtype;
  m public.app_members%rowtype;
  descr text := nullif(trim(coalesce(p_descripcion, '')), '');
  fact text := nullif(upper(trim(coalesce(p_factura, ''))), '');
begin
  perform public.assert_admin();
  perform public.idem_lock('gasto', p_idempotency_key);
  select * into v from public.expenses where idempotency_key = p_idempotency_key;
  if found then return v; end if;

  if p_categoria is null or not (p_categoria = any (public.categorias_gasto())) then
    raise exception 'Elegí la categoría del gasto.' using errcode = 'P0001';
  end if;
  if p_monto is null or p_monto <= 0 then
    raise exception 'Escribí cuánto se gastó.' using errcode = 'P0001';
  end if;
  if p_monto > 999999999 then
    raise exception 'Revisá el monto: es demasiado grande.' using errcode = 'P0001';
  end if;
  if fact is not null and fact !~ '^[0-9A-Z-]{1,30}$' then
    raise exception 'El número de factura solo puede tener números, letras y guiones.' using errcode = 'P0001';
  end if;
  if p_fecha is not null and p_fecha > now() + interval '5 minutes' then
    raise exception 'La fecha del gasto no puede ser posterior a hoy.' using errcode = 'P0001';
  end if;
  if p_fecha is not null and p_fecha < now() - interval '2 years' then
    raise exception 'Revisá la fecha: es de hace más de 2 años.' using errcode = 'P0001';
  end if;

  select * into m from public.app_members where user_id = (select auth.uid());
  insert into public.expenses (category, amount, description, invoice_number, spent_at, created_by, created_by_name, idempotency_key)
  values (p_categoria, p_monto, descr, fact, coalesce(p_fecha, now()), (select auth.uid()), m.full_name, p_idempotency_key)
  returning * into v;
  return v;
end;
$$;
revoke all on function public.registrar_gasto(text, integer, text, text, timestamptz, uuid) from public, anon;
grant execute on function public.registrar_gasto(text, integer, text, text, timestamptz, uuid) to authenticated;

-- Anular un gasto cargado por error (queda en el historial).
create or replace function public.anular_gasto(p_id uuid, p_motivo text) returns public.expenses
language plpgsql security definer set search_path to '' as $$
declare v public.expenses%rowtype;
begin
  perform public.assert_admin();
  if nullif(trim(p_motivo), '') is null then
    raise exception 'Escribí el motivo de la anulación.' using errcode = 'P0001';
  end if;
  select * into v from public.expenses where id = p_id for update;
  if not found then raise exception 'El gasto no existe.' using errcode = 'P0001'; end if;
  if v.status = 'anulado' then return v; end if;
  update public.expenses set status = 'anulado', void_reason = trim(p_motivo), voided_at = now() where id = p_id returning * into v;
  return v;
end;
$$;
revoke all on function public.anular_gasto(uuid, text) from public, anon;
grant execute on function public.anular_gasto(uuid, text) to authenticated;

-- Gastos de un rango: total y por categoría.
create or replace function public.gastos_rango(p_desde timestamptz, p_hasta timestamptz) returns jsonb
language sql stable security definer set search_path to '' as $$
  select jsonb_build_object(
    'total', coalesce(sum(amount), 0),
    'count', count(*),
    'by_category', coalesce((
      select jsonb_agg(jsonb_build_object('category', category, 'amount', total, 'count', cant) order by total desc)
      from (select category, sum(amount) total, count(*) cant from public.expenses
            where status = 'activo' and spent_at >= p_desde and spent_at < p_hasta group by category) c), '[]'::jsonb))
  from public.expenses where status = 'activo' and spent_at >= p_desde and spent_at < p_hasta;
$$;
revoke all on function public.gastos_rango(timestamptz, timestamptz) from public, anon, authenticated;

-- Reporte de ventas y resumen de Inicio: con los gastos (para la ganancia real).
do $$
declare d text;
begin
  d := pg_get_functiondef('public.sales_report(date,date)'::regprocedure);
  if position('gastos_rango' in d) = 0 then
    if position('return v_result;' in d) = 0 then raise exception 'sin return en sales_report'; end if;
    d := replace(d, 'return v_result;', 'v_result := v_result || jsonb_build_object(''expenses'', public.gastos_rango(v_from, v_to));' || chr(10) || '  return v_result;');
    execute d;
  end if;

  d := pg_get_functiondef('public.dashboard_summary()'::regprocedure);
  if position('gastos_rango' in d) = 0 then
    if position('return v_result;' in d) = 0 then raise exception 'sin return en dashboard_summary'; end if;
    d := replace(d, 'return v_result;',
      'v_result := v_result || jsonb_build_object(''expenses'', jsonb_build_object(' || chr(10) ||
      '    ''today'', public.gastos_rango(v_today::timestamp at time zone ''America/Asuncion'', (v_today + 1)::timestamp at time zone ''America/Asuncion''),' || chr(10) ||
      '    ''week'', public.gastos_rango(v_week::timestamp at time zone ''America/Asuncion'', (v_today + 1)::timestamp at time zone ''America/Asuncion''),' || chr(10) ||
      '    ''month'', public.gastos_rango(v_month::timestamp at time zone ''America/Asuncion'', (v_today + 1)::timestamp at time zone ''America/Asuncion''),' || chr(10) ||
      '    ''year'', public.gastos_rango(date_trunc(''year'', v_today)::timestamp at time zone ''America/Asuncion'', (v_today + 1)::timestamp at time zone ''America/Asuncion'')));' || chr(10) ||
      '  return v_result;');
    execute d;
  end if;
end $$;
notify pgrst, 'reload schema';
