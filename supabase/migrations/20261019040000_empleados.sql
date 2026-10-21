-- =================================================================
--  EMPLEADOS (vendedores)
--  - El administrador crea los usuarios (Edge Function "empleados").
--  - Un vendedor solo puede vender y hacer presupuestos: el servidor
--    rechaza compras, stock, anulaciones, devoluciones y reportes.
--  - Cada venta y presupuesto guarda quién la hizo (nombre y apellido).
-- =================================================================

-- 1) Rol, nombre, usuario y estado de cada miembro.
alter table public.app_members
  add column if not exists role text not null default 'vendedor',
  add column if not exists full_name text,
  add column if not exists username text,
  add column if not exists active boolean not null default true;

alter table public.app_members add constraint app_members_role_ok check (role in ('admin', 'vendedor'));
alter table public.app_members add constraint app_members_full_name_ok check (full_name is null or public.texto_ok(full_name, 80, 2));
alter table public.app_members add constraint app_members_username_ok check (username is null or username ~ '^[a-z0-9._-]{3,30}$');
create unique index if not exists app_members_username_unique on public.app_members (lower(username)) where username is not null;

-- El administrador actual (Cesar).
update public.app_members m
set role = 'admin', full_name = coalesce(m.full_name, nullif(trim(u.raw_user_meta_data->>'full_name'), ''), 'Administrador')
from auth.users u
where u.id = m.user_id and u.raw_app_meta_data->>'role' = 'admin';

-- 2) Miembro activo / administrador.
create or replace function public.is_member() returns boolean
language sql stable security definer set search_path to '' as $$
  select exists (select 1 from public.app_members where user_id = (select auth.uid()) and active);
$$;

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path to '' as $$
  select exists (select 1 from public.app_members where user_id = (select auth.uid()) and active and role = 'admin');
$$;
revoke all on function public.is_admin() from public, anon;
grant execute on function public.is_admin() to authenticated;

create or replace function public.assert_admin() returns void
language plpgsql security definer set search_path to '' as $$
begin
  perform public.assert_can_write();
  if not public.is_admin() then
    raise exception 'Solo el administrador puede hacer esta operación.' using errcode = '42501';
  end if;
end;
$$;
revoke all on function public.assert_admin() from public, anon, authenticated;

-- 3) Operaciones solo del administrador: compras, stock, averiados, cargas,
--    anular ventas o compras y devoluciones.
do $$
declare
  f regprocedure;
  d text;
begin
  foreach f in array array[
    'public.create_purchase(jsonb,text,text,text,uuid,date)'::regprocedure,
    'public.create_purchase(jsonb,text,text,text,uuid)'::regprocedure,
    'public.adjust_stock(uuid,numeric,text,integer,uuid)'::regprocedure,
    'public.adjust_stock(uuid,numeric,text,integer)'::regprocedure,
    'public.register_damage(uuid,numeric,text,uuid)'::regprocedure,
    'public.void_purchase(uuid,text)'::regprocedure,
    'public.close_load(uuid)'::regprocedure,
    'public.void_sale(uuid,text)'::regprocedure,
    'public.return_sale(uuid,jsonb,text,uuid)'::regprocedure
  ] loop
    d := pg_get_functiondef(f);
    if position('perform public.assert_admin();' in d) > 0 then continue; end if;
    if position('perform public.assert_can_write();' in d) = 0 then
      raise exception 'No se encontró el control de permisos en %', f;
    end if;
    execute replace(d, 'perform public.assert_can_write();', 'perform public.assert_admin();');
  end loop;

  -- Reportes, resumen de Inicio y estado de cargas (muestran costos y ganancias).
  foreach f in array array[
    'public.dashboard_summary()'::regprocedure,
    'public.sales_report(date,date)'::regprocedure
  ] loop
    d := pg_get_functiondef(f);
    if position('public.is_admin()' in d) > 0 then continue; end if;
    execute regexp_replace(d, '\mbegin\M',
      'begin if not public.is_admin() then raise exception ''Solo el administrador puede ver los reportes.'' using errcode = ''42501''; end if;');
  end loop;

  d := pg_get_functiondef('public.load_status(uuid)'::regprocedure);
  if position('public.is_admin()' in d) = 0 then
    execute replace(d, 'public.is_member()', 'public.is_admin()');
  end if;
end $$;

-- 4) Tablas: el vendedor lee productos (para vender) y maneja clientes;
--    productos, proveedores, datos del negocio, compras y movimientos son del administrador.
--    (Se modifican las reglas existentes en lugar de borrarlas y crearlas de nuevo.)
alter policy members_all on public.products using ((select public.is_admin())) with check ((select public.is_admin()));
alter policy members_all on public.products rename to admins_write;
create policy members_read on public.products for select to authenticated using ((select public.is_member()));

alter policy members_all on public.suppliers using ((select public.is_admin())) with check ((select public.is_admin()));
alter policy members_all on public.suppliers rename to admins_all;

alter policy members_update on public.business_settings using ((select public.is_admin())) with check ((select public.is_admin()));
alter policy members_update on public.business_settings rename to admins_update;

alter policy members_read on public.purchases using ((select public.is_admin()));
alter policy members_read on public.purchases rename to admins_read;
alter policy members_read on public.purchase_items using ((select public.is_admin()));
alter policy members_read on public.purchase_items rename to admins_read;
alter policy members_read on public.stock_movements using ((select public.is_admin()));
alter policy members_read on public.stock_movements rename to admins_read;
alter policy members_read on public.product_loads using ((select public.is_admin()));
alter policy members_read on public.product_loads rename to admins_read;

-- Empleados: el administrador ve a todos; cada uno, su propia fila.
create policy admins_read_all on public.app_members for select to authenticated using ((select public.is_admin()));

-- Nota: las reglas del bucket "business" (logo) son de Supabase y no se pueden cambiar
-- desde SQL; igual, el vendedor no puede cambiar business_settings (la URL del logo).

-- 5) Quién hizo cada venta y presupuesto (nombre y apellido, con fecha y hora en created_at).
alter table public.sales add column if not exists seller_name text;
alter table public.quotes add column if not exists seller_name text;

create or replace function public.set_seller() returns trigger
language plpgsql security definer set search_path to '' as $$
begin
  new.created_by := coalesce((select auth.uid()), new.created_by);
  new.seller_name := coalesce(
    (select full_name from public.app_members where user_id = new.created_by),
    new.seller_name);
  return new;
end;
$$;
revoke all on function public.set_seller() from public, anon, authenticated;

create trigger sales_set_seller before insert on public.sales for each row execute function public.set_seller();
create trigger quotes_set_seller before insert on public.quotes for each row execute function public.set_seller();

-- Lo ya cargado: a nombre de quien lo creó.
update public.sales s set seller_name = m.full_name from public.app_members m where m.user_id = s.created_by and s.seller_name is null;
update public.quotes q set seller_name = m.full_name from public.app_members m where m.user_id = q.created_by and q.seller_name is null;
