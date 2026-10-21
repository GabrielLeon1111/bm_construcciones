-- =====================================================================
--  Averiados: mercadería rota, mojada, vencida o perdida.
--  Descuenta stock, queda en el historial como ajuste/'averia' con el costo
--  promedio del momento (para saber cuánta plata se perdió) y aparece
--  en el arqueo como "Pérdida por averiados".
--  Requiere 20261018190000_idempotencia_y_stock.sql (idem_lock,
--  allow_stock_write y las columnas de clave en stock_movements).
-- =====================================================================

-- Se marca como ajuste con subtipo 'averia' (no hace falta tocar la regla de tipos).
alter table public.stock_movements
  add column if not exists movement_subtype text
  constraint stock_movements_subtype_ok check (movement_subtype is null or (movement_subtype = 'averia' and movement_type = 'ajuste'));

create or replace function public.register_damage(
  p_product_id uuid,
  p_quantity numeric,
  p_reason text,
  p_idempotency_key uuid default null
)
returns public.stock_movements
language plpgsql security definer set search_path = '' as $$
declare
  v_product public.products%rowtype;
  v_movement public.stock_movements%rowtype;
  v_hash text;
begin
  perform public.assert_can_write();
  perform public.idem_lock('damage', p_idempotency_key);

  v_hash := md5(jsonb_build_object('product', p_product_id, 'quantity', p_quantity, 'reason', nullif(trim(p_reason), ''))::text);

  select * into v_movement from public.stock_movements where idempotency_key = p_idempotency_key;
  if found then
    if v_movement.request_hash is distinct from v_hash then
      raise exception 'Estos averiados ya se habían registrado con otros datos. Revisá el historial del producto.'
        using errcode = 'BM409';
    end if;
    return v_movement;
  end if;

  if p_quantity is null or p_quantity <= 0 or p_quantity > 100000 then
    raise exception 'Escribí cuántas se averiaron.' using errcode = 'P0001';
  end if;
  if nullif(trim(p_reason), '') is null or char_length(trim(p_reason)) > 150 then
    raise exception 'Escribí qué pasó (máximo 150 letras).' using errcode = 'P0001';
  end if;

  select * into v_product from public.products where id = p_product_id for update;
  if not found then raise exception 'El producto no existe.' using errcode = 'P0001'; end if;
  if p_quantity > v_product.stock then
    raise exception 'No puede ser más de lo que hay (quedan %).',
      trim(trailing '.' from trim(trailing '0' from v_product.stock::text)) using errcode = 'P0001';
  end if;

  perform public.allow_stock_write();
  update public.products set stock = stock - p_quantity where id = v_product.id;

  insert into public.stock_movements (
    product_id, movement_type, movement_subtype, quantity, stock_before, stock_after,
    unit_cost, avg_cost_before, avg_cost_after, reason, idempotency_key, request_hash
  ) values (
    v_product.id, 'ajuste', 'averia', -p_quantity, v_product.stock, v_product.stock - p_quantity,
    v_product.avg_cost, v_product.avg_cost, v_product.avg_cost, trim(p_reason), p_idempotency_key, v_hash
  ) returning * into v_movement;

  return v_movement;
end;
$$;

revoke all on function public.register_damage(uuid, numeric, text, uuid) from public, anon;
grant execute on function public.register_damage(uuid, numeric, text, uuid) to authenticated;

-- Arqueo: se agrega la pérdida por averiados del período.
create or replace function public.sales_report(p_from date, p_to date)
returns jsonb
language plpgsql stable security invoker set search_path = '' as $$
declare
  v_from timestamptz := p_from::timestamp at time zone 'America/Asuncion';
  v_to timestamptz := (p_to + 1)::timestamp at time zone 'America/Asuncion';
  v_result jsonb;
begin
  if p_from is null or p_to is null or p_to < p_from then
    raise exception 'Revisá el rango de fechas.' using errcode = 'P0001';
  end if;

  select jsonb_build_object(
    'invested', (select coalesce(sum(total), 0) from public.purchases
                  where status = 'activa' and created_at >= v_from and created_at < v_to),
    'purchases_count', (select count(*) from public.purchases
                  where status = 'activa' and created_at >= v_from and created_at < v_to),
    'damaged', (select coalesce(sum(round(-quantity * coalesce(unit_cost, 0))), 0) from public.stock_movements
                  where movement_subtype = 'averia' and created_at >= v_from and created_at < v_to),
    'sales', coalesce(sum(total), 0),
    'cost', coalesce(sum(cost_total), 0),
    'profit', coalesce(sum(total - cost_total), 0),
    'discounts', coalesce(sum(discount), 0),
    'count', count(*),
    'voided_count', (select count(*) from public.sales
                  where status = 'anulada' and created_at >= v_from and created_at < v_to),
    'payments', jsonb_build_object(
      'efectivo', coalesce(sum(total) filter (where payment_method = 'efectivo'), 0),
      'transferencia', coalesce(sum(total) filter (where payment_method = 'transferencia'), 0),
      'qr', coalesce(sum(total) filter (where payment_method = 'qr'), 0)),
    'products', (
      select coalesce(jsonb_agg(x order by (x->>'profit')::bigint desc), '[]'::jsonb) from (
        select jsonb_build_object(
          'name', description, 'category', min(category), 'unit', min(unit),
          'quantity', sum(quantity), 'sales', sum(net_revenue),
          'cost', sum(cost), 'profit', sum(net_revenue - cost)) as x
        from public.v_sale_lines
        where created_at >= v_from and created_at < v_to
        group by description
      ) t)
  ) into v_result
  from public.sales
  where status = 'activa' and created_at >= v_from and created_at < v_to;

  return v_result;
end;
$$;
