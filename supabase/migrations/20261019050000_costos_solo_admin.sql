-- =================================================================
--  COSTOS SOLO PARA EL ADMINISTRADOR
--  El vendedor no puede leer costos ni ganancias, ni siquiera llamando
--  al servidor directamente:
--   - Columnas de costo sin permiso de lectura (avg_cost, cost_total,
--     returned_cost, unit_cost).
--   - El administrador las lee con funciones que verifican que lo sea
--     (productos_admin, ventas_admin).
--   - Lo que devuelven create_sale / set_sale_client va sin costos al vendedor.
--   - Devoluciones (tienen costos): solo el administrador.
--   - Bucket del logo: solo imágenes PNG/JPG/WebP de hasta 2 MB.
-- =================================================================

create or replace function public.productos_admin() returns setof public.products
language plpgsql stable security definer set search_path to '' as $$
begin
  if not public.is_admin() then
    raise exception 'Solo el administrador puede ver los costos.' using errcode = '42501';
  end if;
  return query select * from public.products;
end;
$$;
revoke all on function public.productos_admin() from public, anon;
grant execute on function public.productos_admin() to authenticated;

create or replace function public.ventas_admin(
  p_from timestamptz default null,
  p_to timestamptz default null,
  p_client uuid default null,
  p_id uuid default null,
  p_limit int default 300
) returns jsonb
language plpgsql stable security definer set search_path to '' as $$
declare v jsonb;
begin
  if not public.is_admin() then
    raise exception 'Solo el administrador puede ver los costos.' using errcode = '42501';
  end if;
  select coalesce(jsonb_agg(x order by (x->>'created_at') desc), '[]'::jsonb) into v
  from (
    select to_jsonb(s) || jsonb_build_object('sale_items',
      coalesce((select jsonb_agg(to_jsonb(i) order by i.position) from public.sale_items i where i.sale_id = s.id), '[]'::jsonb)) as x
    from public.sales s
    where (p_from is null or s.created_at >= p_from)
      and (p_to is null or s.created_at < p_to)
      and (p_client is null or s.client_id = p_client)
      and (p_id is null or s.id = p_id)
    order by s.created_at desc
    limit least(greatest(coalesce(p_limit, 300), 1), 1000)
  ) t;
  return v;
end;
$$;
revoke all on function public.ventas_admin(timestamptz, timestamptz, uuid, uuid, int) from public, anon;
grant execute on function public.ventas_admin(timestamptz, timestamptz, uuid, uuid, int) to authenticated;

create or replace function public.sin_costos(s public.sales) returns public.sales
language plpgsql stable security definer set search_path to '' as $$
begin
  if not public.is_admin() then
    s.cost_total := 0;
    s.returned_cost := 0;
  end if;
  return s;
end;
$$;
revoke all on function public.sin_costos(public.sales) from public, anon, authenticated;

do $$
declare f regprocedure; d text;
begin
  foreach f in array array[
    'public.create_sale(jsonb,text,uuid,integer,text,uuid,uuid,integer,integer,integer)'::regprocedure,
    'public.create_sale(jsonb,text,uuid,integer,text,uuid,uuid)'::regprocedure,
    'public.set_sale_client(uuid,uuid)'::regprocedure
  ] loop
    d := pg_get_functiondef(f);
    if position('public.sin_costos(' in d) > 0 then continue; end if;
    execute replace(d, 'return v_sale;', 'return public.sin_costos(v_sale);');
  end loop;
end $$;

-- Reportes con permisos del dueño (ya verifican que sea administrador).
alter function public.dashboard_summary() security definer;
alter function public.sales_report(date, date) security definer;

alter policy members_read on public.sale_returns using ((select public.is_admin()));
alter policy members_read on public.sale_returns rename to admins_read;
alter policy members_read on public.sale_return_items using ((select public.is_admin()));
alter policy members_read on public.sale_return_items rename to admins_read;

-- Columnas de costos sin lectura directa.
revoke select on public.products from authenticated, anon;
grant select (id, name, category, brand, unit, stock, sale_price, min_stock, active, notes, created_at, updated_at, sold_by_load)
  on public.products to authenticated;

revoke select on public.sales from authenticated, anon;
grant select (id, number, client_id, client_name, client_phone, client_document, client_address, payment_method, subtotal, discount,
  total, notes, quote_id, status, void_reason, voided_at, idempotency_key, created_by, created_at, request_hash, returned_amount,
  paid_cash, paid_transfer, cash_received, change_amount, seller_name)
  on public.sales to authenticated;

revoke select on public.sale_items from authenticated, anon;
grant select (id, sale_id, position, product_id, description, unit, quantity, unit_price, is_gift, line_total, load_id, returned_qty, price_is_total)
  on public.sale_items to authenticated;

-- Logo: solo imágenes chicas.
update storage.buckets set allowed_mime_types = array['image/png','image/jpeg','image/webp'], file_size_limit = 2097152 where id = 'business';
