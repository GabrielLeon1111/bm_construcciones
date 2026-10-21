-- =====================================================================
--  Métodos de pago: Efectivo, Transferencia y Mixto.
--   * Efectivo: se anota con cuánto pagó y el vuelto (lo recibido tiene
--     que alcanzar el total).
--   * Mixto: parte en efectivo y parte por transferencia; la suma tiene
--     que dar exactamente el total.
--   * Cada venta guarda cuánto entró en efectivo (paid_cash) y cuánto por
--     transferencia (paid_transfer): el inicio y el arqueo desglosan así.
--  create_sale pasa a tener 10 parámetros (la versión vieja de 7 queda
--  sin permiso de uso).
-- =====================================================================

alter table public.sales
  add column if not exists paid_cash integer not null default 0,
  add column if not exists paid_transfer integer not null default 0,
  add column if not exists cash_received integer,
  add column if not exists change_amount integer not null default 0;

update public.sales set
  paid_cash = case when payment_method = 'efectivo' then total else 0 end,
  paid_transfer = case when payment_method in ('transferencia', 'qr') then total else 0 end
where paid_cash + paid_transfer <> total;

alter table public.sales drop constraint if exists sales_payment_method_check;
alter table public.sales add constraint sales_payment_method_check
  check (payment_method in ('efectivo', 'transferencia', 'mixto', 'qr'));
alter table public.sales add constraint sales_pago_ok check (
  paid_cash >= 0 and paid_transfer >= 0 and paid_cash + paid_transfer = total
  and change_amount >= 0 and (cash_received is null or public.monto_ok(cash_received)));

create or replace function public.create_sale(
  p_items jsonb,
  p_payment_method text,
  p_client_id uuid default null,
  p_discount integer default 0,
  p_notes text default null,
  p_quote_id uuid default null,
  p_idempotency_key uuid default null,
  p_paid_cash integer default null,
  p_paid_transfer integer default null,
  p_cash_received integer default null
)
returns public.sales
language plpgsql security definer set search_path = '' as $$
declare
  v_sale public.sales%rowtype;
  v_quote public.quotes%rowtype;
  v_client public.clients%rowtype;
  v_product public.products%rowtype;
  v_item jsonb;
  v_pos int := 0;
  v_qty numeric(14,3);
  v_price int;
  v_gift boolean;
  v_por_linea boolean;
  v_line int;
  v_cost int;
  v_subtotal int := 0;
  v_cost_total int := 0;
  v_total int;
  v_cash int := 0;
  v_transfer int := 0;
  v_change int := 0;
  v_desc text;
  v_unit text;
  v_hash text;
  v_load uuid;
  v_recovered int;
begin
  perform public.assert_can_write();
  perform public.idem_lock('sale', p_idempotency_key);

  v_hash := md5(jsonb_build_object(
    'items', p_items, 'payment', p_payment_method, 'client', p_client_id,
    'discount', coalesce(p_discount, 0), 'notes', nullif(trim(p_notes), ''), 'quote', p_quote_id,
    'cash', p_paid_cash, 'transfer', p_paid_transfer, 'received', p_cash_received)::text);

  select * into v_sale from public.sales where idempotency_key = p_idempotency_key;
  if found then
    if v_sale.request_hash is distinct from v_hash then
      raise exception 'Esta venta ya se había registrado (N° %) antes de que la cambiaras. Revisala en Ventas.', v_sale.number
        using errcode = 'BM409';
    end if;
    return v_sale;
  end if;

  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'Agregá al menos un producto a la venta.' using errcode = 'P0001';
  end if;
  if p_payment_method is null or p_payment_method not in ('efectivo', 'transferencia', 'mixto') then
    raise exception 'Elegí el método de pago.' using errcode = 'P0001';
  end if;
  if coalesce(p_discount, 0) < 0 then
    raise exception 'El descuento no puede ser negativo.' using errcode = 'P0001';
  end if;

  if p_quote_id is not null then
    select * into v_quote from public.quotes where id = p_quote_id for update;
    if not found then
      raise exception 'El presupuesto no existe.' using errcode = 'P0001';
    end if;
    if v_quote.status = 'vendido' then
      raise exception 'Este presupuesto ya se convirtió en venta (N° %).',
        (select number from public.sales where id = v_quote.sale_id) using errcode = 'BM409';
    end if;
    if v_quote.status <> 'pendiente' then
      raise exception 'Este presupuesto está anulado; no se puede vender.' using errcode = 'P0001';
    end if;
  end if;

  if p_client_id is not null then
    select * into v_client from public.clients where id = p_client_id;
  end if;

  perform public.allow_stock_write();

  insert into public.sales (
    client_id, client_name, client_phone, client_document, client_address,
    payment_method, notes, quote_id, idempotency_key, request_hash
  ) values (
    v_client.id, v_client.full_name, v_client.phone, v_client.document, v_client.address,
    p_payment_method, nullif(trim(p_notes), ''), p_quote_id, p_idempotency_key, v_hash
  ) returning * into v_sale;

  for v_item in select value from jsonb_array_elements(p_items) loop
    v_pos := v_pos + 1;
    v_qty := (v_item->>'quantity')::numeric;
    v_gift := coalesce((v_item->>'is_gift')::boolean, false);
    v_por_linea := coalesce((v_item->>'price_is_total')::boolean, false) and not v_gift;
    v_price := case when v_gift then 0 else coalesce((v_item->>'unit_price')::int, 0) end;
    if v_qty is null or v_qty <= 0 then
      raise exception 'Revisá las cantidades: todas tienen que ser mayores a cero.' using errcode = 'P0001';
    end if;
    if v_price < 0 then
      raise exception 'El precio no puede ser negativo.' using errcode = 'P0001';
    end if;
    v_line := case when v_por_linea then v_price else round(v_qty * v_price) end;

    v_cost := 0;
    v_load := null;
    v_desc := nullif(trim(v_item->>'description'), '');
    v_unit := coalesce(nullif(trim(v_item->>'unit'), ''), 'unidad');

    if nullif(v_item->>'product_id', '') is not null then
      select * into v_product from public.products
        where id = (v_item->>'product_id')::uuid for update;
      if not found then
        raise exception 'Uno de los productos ya no existe.' using errcode = 'P0001';
      end if;
      v_desc := coalesce(v_desc, v_product.name);
      v_unit := v_product.unit;

      if v_product.sold_by_load then
        v_load := public.open_load(v_product.id);
        select coalesce(sum(round(si.quantity * si.unit_cost)), 0) into v_recovered
          from public.sale_items si join public.sales sa on sa.id = si.sale_id
          where si.load_id = v_load and sa.status = 'activa';
        v_cost := round(least(v_line, greatest(public.load_paid(v_load) - v_recovered, 0)) / v_qty);
      else
        if v_product.stock < v_qty then
          raise exception 'No hay stock suficiente de "%" (quedan %).',
            v_product.name, trim(trailing '.' from trim(trailing '0' from v_product.stock::text))
            using errcode = 'P0001';
        end if;
        v_cost := v_product.avg_cost;

        update public.products set stock = stock - v_qty where id = v_product.id;

        insert into public.stock_movements (
          product_id, movement_type, quantity, stock_before, stock_after,
          unit_cost, avg_cost_before, avg_cost_after, unit_price, sale_id
        ) values (
          v_product.id, 'venta', -v_qty, v_product.stock, v_product.stock - v_qty,
          v_product.avg_cost, v_product.avg_cost, v_product.avg_cost, v_price, v_sale.id
        );
      end if;
    elsif v_desc is null then
      raise exception 'Cada línea necesita un producto o una descripción.' using errcode = 'P0001';
    end if;

    v_subtotal := v_subtotal + v_line;
    v_cost_total := v_cost_total + round(v_qty * v_cost);

    insert into public.sale_items (
      sale_id, position, product_id, description, unit, quantity,
      unit_price, unit_cost, is_gift, line_total, load_id, price_is_total
    ) values (
      v_sale.id, v_pos, v_product.id, v_desc, v_unit, v_qty,
      v_price, v_cost, v_gift, v_line, v_load, v_por_linea
    );
    v_product := null;
  end loop;

  if coalesce(p_discount, 0) > v_subtotal then
    raise exception 'El descuento no puede ser mayor al total.' using errcode = 'P0001';
  end if;
  v_total := v_subtotal - coalesce(p_discount, 0);

  -- Cómo se pagó.
  if p_payment_method = 'efectivo' then
    v_cash := v_total;
    if p_cash_received is not null then
      if p_cash_received < v_total then
        raise exception 'Lo que paga en efectivo (Gs. %) no alcanza el total (Gs. %).', p_cash_received, v_total using errcode = 'P0001';
      end if;
      v_change := p_cash_received - v_total;
    end if;
  elsif p_payment_method = 'transferencia' then
    v_transfer := v_total;
  else
    if p_paid_cash is null or p_paid_transfer is null or p_paid_cash < 0 or p_paid_transfer < 0 then
      raise exception 'En el pago mixto poné cuánto en efectivo y cuánto por transferencia.' using errcode = 'P0001';
    end if;
    if p_paid_cash + p_paid_transfer <> v_total then
      raise exception 'Efectivo + transferencia tiene que dar exactamente el total (Gs. %).', v_total using errcode = 'P0001';
    end if;
    v_cash := p_paid_cash;
    v_transfer := p_paid_transfer;
  end if;

  update public.sales set
    subtotal = v_subtotal,
    discount = coalesce(p_discount, 0),
    total = v_total,
    cost_total = v_cost_total,
    paid_cash = v_cash,
    paid_transfer = v_transfer,
    cash_received = case when p_payment_method = 'efectivo' then p_cash_received end,
    change_amount = v_change
  where id = v_sale.id
  returning * into v_sale;

  if p_quote_id is not null then
    update public.quotes set status = 'vendido', sale_id = v_sale.id where id = p_quote_id;
  end if;

  return v_sale;
end;
$$;

revoke all on function public.create_sale(jsonb, text, uuid, integer, text, uuid, uuid) from public, anon, authenticated;
revoke all on function public.create_sale(jsonb, text, uuid, integer, text, uuid, uuid, integer, integer, integer) from public, anon;
grant execute on function public.create_sale(jsonb, text, uuid, integer, text, uuid, uuid, integer, integer, integer) to authenticated;

-- ============ Arqueo: efectivo y transferencia según lo cobrado (sin lo devuelto) ============
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
    'returned', coalesce(sum(returned_amount), 0),
    'sales', coalesce(sum(total - returned_amount), 0),
    'cost', coalesce(sum(cost_total - returned_cost), 0),
    'profit', coalesce(sum((total - returned_amount) - (cost_total - returned_cost)), 0),
    'discounts', coalesce(sum(discount), 0),
    'count', count(*),
    'voided_count', (select count(*) from public.sales
                  where status = 'anulada' and created_at >= v_from and created_at < v_to),
    'payments', jsonb_build_object(
      'efectivo', coalesce(sum(case when total > 0 then round(paid_cash::numeric * (total - returned_amount) / total) else 0 end), 0),
      'transferencia', coalesce(sum(case when total > 0 then round(paid_transfer::numeric * (total - returned_amount) / total) else 0 end), 0),
      'qr', 0,
      'mixtas', count(*) filter (where payment_method = 'mixto')),
    'products', (
      select coalesce(jsonb_agg(x order by (x->>'profit')::bigint desc), '[]'::jsonb) from (
        select jsonb_build_object(
          'name', description, 'category', min(category), 'unit', min(unit),
          'quantity', sum(quantity), 'sales', sum(net_revenue),
          'cost', sum(cost), 'profit', sum(net_revenue - cost)) as x
        from public.v_sale_lines
        where created_at >= v_from and created_at < v_to and quantity > 0
        group by description
      ) t)
  ) into v_result
  from public.sales
  where status = 'activa' and created_at >= v_from and created_at < v_to;

  return v_result;
end;
$$;

create or replace function public.dashboard_summary()
returns jsonb
language plpgsql stable set search_path = '' as $$
declare
  v_today date := (now() at time zone 'America/Asuncion')::date;
  v_week date := date_trunc('week', v_today)::date;
  v_month date := date_trunc('month', v_today)::date;
  v_prev_month date := (date_trunc('month', v_today) - interval '1 month')::date;
  v_year date := date_trunc('year', v_today)::date;
  v_result jsonb;
begin
  with s as (
    -- Ventas netas: sin lo devuelto. Lo cobrado en efectivo y transferencia, proporcional.
    select (total - returned_amount) as total, (cost_total - returned_cost) as cost_total,
           case when total > 0 then round(paid_cash::numeric * (total - returned_amount) / total) else 0 end as cash,
           case when total > 0 then round(paid_transfer::numeric * (total - returned_amount) / total) else 0 end as transfer,
           (created_at at time zone 'America/Asuncion')::date as d
    from public.sales
    where status = 'activa'
      and created_at >= (date_trunc('month', v_today) - interval '12 months')::timestamp at time zone 'America/Asuncion'
  ),
  periods as (
    select jsonb_build_object(
      'today', jsonb_build_object('sales', coalesce(sum(total) filter (where d = v_today), 0),
                                  'profit', coalesce(sum(total - cost_total) filter (where d = v_today), 0),
                                  'count', count(*) filter (where d = v_today)),
      'week', jsonb_build_object('sales', coalesce(sum(total) filter (where d >= v_week), 0),
                                 'profit', coalesce(sum(total - cost_total) filter (where d >= v_week), 0),
                                 'count', count(*) filter (where d >= v_week)),
      'month', jsonb_build_object('sales', coalesce(sum(total) filter (where d >= v_month), 0),
                                  'profit', coalesce(sum(total - cost_total) filter (where d >= v_month), 0),
                                  'count', count(*) filter (where d >= v_month)),
      'prev_month', jsonb_build_object('sales', coalesce(sum(total) filter (where d >= v_prev_month and d < v_month), 0),
                                       'profit', coalesce(sum(total - cost_total) filter (where d >= v_prev_month and d < v_month), 0),
                                       'count', count(*) filter (where d >= v_prev_month and d < v_month)),
      'payments', jsonb_build_object(
        'efectivo', coalesce(sum(cash) filter (where d >= v_month), 0),
        'transferencia', coalesce(sum(transfer) filter (where d >= v_month), 0),
        'qr', 0),
      'payments_today', jsonb_build_object(
        'efectivo', coalesce(sum(cash) filter (where d = v_today), 0),
        'transferencia', coalesce(sum(transfer) filter (where d = v_today), 0),
        'qr', 0)
    ) as j
    from s
  ),
  yearly as (
    select jsonb_build_object(
      'sales', coalesce(sum(total - returned_amount), 0),
      'profit', coalesce(sum((total - returned_amount) - (cost_total - returned_cost)), 0),
      'count', count(*)) as j
    from public.sales
    where status = 'activa'
      and created_at >= v_year::timestamp at time zone 'America/Asuncion'
  ),
  series as (
    select coalesce(jsonb_agg(jsonb_build_object(
      'month', to_char(m, 'YYYY-MM'),
      'sales', coalesce((select sum(total) from s where date_trunc('month', d) = m), 0),
      'profit', coalesce((select sum(total - cost_total) from s where date_trunc('month', d) = m), 0)
    ) order by m), '[]'::jsonb) as j
    from generate_series(date_trunc('month', v_today) - interval '11 months', date_trunc('month', v_today), interval '1 month') m
  ),
  month_lines as (
    select * from public.v_sale_lines
    where created_at >= v_month::timestamp at time zone 'America/Asuncion' and quantity > 0
  ),
  by_category as (
    select coalesce(jsonb_agg(x order by (x->>'sales')::bigint desc), '[]'::jsonb) as j from (
      select jsonb_build_object('category', category,
                                'sales', sum(net_revenue),
                                'profit', sum(net_revenue - cost)) as x
      from month_lines group by category
    ) t
  ),
  top_products as (
    select coalesce(jsonb_agg(x order by (x->>'sales')::bigint desc), '[]'::jsonb) as j from (
      select jsonb_build_object('name', description, 'unit', min(unit),
                                'quantity', sum(quantity),
                                'sales', sum(net_revenue),
                                'profit', sum(net_revenue - cost)) as x
      from month_lines group by description
      order by sum(net_revenue) desc, sum(quantity) desc
      limit 5
    ) t
  ),
  inventory as (
    select jsonb_build_object(
      'capital', coalesce(sum(round(stock * avg_cost)) filter (where active and not sold_by_load), 0),
      'low_stock', count(*) filter (where active and not sold_by_load and stock > 0 and stock <= min_stock),
      'out_of_stock', count(*) filter (where active and not sold_by_load and stock = 0),
      'products', count(*) filter (where active)
    ) as j
    from public.products
  ),
  low_list as (
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', id, 'name', name, 'unit', unit, 'stock', stock, 'min_stock', min_stock) order by stock, name), '[]'::jsonb) as j
    from (
      select * from public.products
      where active and not sold_by_load and stock <= min_stock
      order by stock, name limit 8
    ) t
  )
  select (select j from periods)
         || jsonb_build_object(
              'year', (select j from yearly),
              'series', (select j from series),
              'by_category', (select j from by_category),
              'top_products', (select j from top_products),
              'inventory', (select j from inventory),
              'low_stock_list', (select j from low_list))
    into v_result;

  return v_result;
end;
$$;
