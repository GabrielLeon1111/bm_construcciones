-- =====================================================================
--  Productos por carga (arena, piedra, ripio, tierra...)
--
--  Lo que trae el camión nunca es exacto, así que estos productos NO
--  cuentan stock. En vez de eso se lleva la cuenta por carga:
--    * cada compra se suma a la carga abierta (si no hay, se abre una);
--    * cada venta (por palada, con cuartos: 1/4, 1/2...) se suma a la carga;
--    * mientras está abierta, cada venta primero "recupera" lo pagado
--      (costo provisorio) y lo que pasa de eso es ganancia;
--    * al tocar "Se terminó la carga" se reparte el costo real entre todas
--      las ventas de esa carga, así el inicio y el arqueo quedan exactos.
--  Una carga nueva que llega antes de terminar la anterior se suma a la
--  misma (es la misma pila).
--  Requiere 20261018190000_idempotencia_y_stock.sql.
-- =====================================================================

alter table public.products add column if not exists sold_by_load boolean not null default false;

create table if not exists public.product_loads (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete restrict,
  status text not null default 'abierta' check (status in ('abierta', 'cerrada')),
  opened_at timestamptz not null default now(),
  closed_at timestamptz,
  -- Resultado final, guardado al cerrar.
  final_paid integer check (final_paid is null or final_paid >= 0),
  final_sold integer check (final_sold is null or final_sold >= 0)
);
-- Una sola carga abierta por producto.
create unique index if not exists product_loads_one_open on public.product_loads (product_id) where status = 'abierta';
create index if not exists product_loads_product_idx on public.product_loads (product_id, opened_at desc);

alter table public.sale_items add column if not exists load_id uuid references public.product_loads(id) on delete set null;
alter table public.purchase_items add column if not exists load_id uuid references public.product_loads(id) on delete set null;
create index if not exists sale_items_load_idx on public.sale_items (load_id);
create index if not exists purchase_items_load_idx on public.purchase_items (load_id);

alter table public.product_loads enable row level security;
create policy members_read on public.product_loads for select to authenticated using ((select public.is_member()));
grant select on public.product_loads to authenticated;

-- La carga abierta de un producto (la crea si no hay). Uso interno.
create or replace function public.open_load(p_product_id uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid;
begin
  select id into v_id from public.product_loads where product_id = p_product_id and status = 'abierta';
  if not found then
    insert into public.product_loads (product_id) values (p_product_id) returning id into v_id;
  end if;
  return v_id;
end;
$$;

-- Lo pagado en una carga (compras activas).
create or replace function public.load_paid(p_load_id uuid)
returns integer language sql stable security definer set search_path = '' as $$
  select coalesce(sum(pi.line_total), 0)::int
  from public.purchase_items pi join public.purchases pu on pu.id = pi.purchase_id
  where pi.load_id = p_load_id and pu.status = 'activa';
$$;

-- Lo vendido en una carga (ventas activas, con el descuento repartido).
create or replace function public.load_sold(p_load_id uuid)
returns integer language sql stable security definer set search_path = '' as $$
  select coalesce(sum(case when sa.subtotal > 0 then round(si.line_total::numeric * sa.total / sa.subtotal) else 0 end), 0)::int
  from public.sale_items si join public.sales sa on sa.id = si.sale_id
  where si.load_id = p_load_id and sa.status = 'activa';
$$;

-- ============ create_sale: los productos por carga no tocan stock ============
create or replace function public.create_sale(
  p_items jsonb,
  p_payment_method text,
  p_client_id uuid default null,
  p_discount integer default 0,
  p_notes text default null,
  p_quote_id uuid default null,
  p_idempotency_key uuid default null
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
  v_line int;
  v_cost int;
  v_subtotal int := 0;
  v_cost_total int := 0;
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
    'discount', coalesce(p_discount, 0), 'notes', nullif(trim(p_notes), ''), 'quote', p_quote_id)::text);

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
  if p_payment_method is null or p_payment_method not in ('efectivo', 'transferencia', 'qr') then
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
    v_price := case when v_gift then 0 else coalesce((v_item->>'unit_price')::int, 0) end;
    if v_qty is null or v_qty <= 0 then
      raise exception 'Revisá las cantidades: todas tienen que ser mayores a cero.' using errcode = 'P0001';
    end if;
    if v_price < 0 then
      raise exception 'El precio no puede ser negativo.' using errcode = 'P0001';
    end if;

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
        -- Por carga: sin stock. Costo provisorio: primero se recupera lo pagado.
        v_load := public.open_load(v_product.id);
        select coalesce(sum(round(si.quantity * si.unit_cost)), 0) into v_recovered
          from public.sale_items si join public.sales sa on sa.id = si.sale_id
          where si.load_id = v_load and sa.status = 'activa';
        v_cost := round(least(round(v_qty * v_price), greatest(public.load_paid(v_load) - v_recovered, 0)) / v_qty);
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

    v_line := round(v_qty * v_price);
    v_subtotal := v_subtotal + v_line;
    v_cost_total := v_cost_total + round(v_qty * v_cost);

    insert into public.sale_items (
      sale_id, position, product_id, description, unit, quantity,
      unit_price, unit_cost, is_gift, line_total, load_id
    ) values (
      v_sale.id, v_pos, v_product.id, v_desc, v_unit, v_qty,
      v_price, v_cost, v_gift, v_line, v_load
    );
    v_product := null;
  end loop;

  if coalesce(p_discount, 0) > v_subtotal then
    raise exception 'El descuento no puede ser mayor al total.' using errcode = 'P0001';
  end if;

  update public.sales set
    subtotal = v_subtotal,
    discount = coalesce(p_discount, 0),
    total = v_subtotal - coalesce(p_discount, 0),
    cost_total = v_cost_total
  where id = v_sale.id
  returning * into v_sale;

  if p_quote_id is not null then
    update public.quotes set status = 'vendido', sale_id = v_sale.id where id = p_quote_id;
  end if;

  return v_sale;
end;
$$;

-- ============ create_purchase: por carga se suma a la carga abierta ============
create or replace function public.create_purchase(
  p_items jsonb,
  p_supplier text default null,
  p_invoice_number text default null,
  p_notes text default null,
  p_idempotency_key uuid default null
)
returns public.purchases
language plpgsql security definer set search_path = '' as $$
declare
  v_purchase public.purchases%rowtype;
  v_product public.products%rowtype;
  v_item jsonb;
  v_pos int := 0;
  v_qty numeric(14,3);
  v_cost int;
  v_new_price int;
  v_new_avg int;
  v_line int;
  v_total int := 0;
  v_hash text;
  v_load uuid;
begin
  perform public.assert_can_write();
  perform public.idem_lock('purchase', p_idempotency_key);

  v_hash := md5(jsonb_build_object(
    'items', p_items, 'supplier', nullif(trim(p_supplier), ''),
    'invoice', nullif(trim(p_invoice_number), ''), 'notes', nullif(trim(p_notes), ''))::text);

  select * into v_purchase from public.purchases where idempotency_key = p_idempotency_key;
  if found then
    if v_purchase.request_hash is distinct from v_hash then
      raise exception 'Esta compra ya se había registrado (N° %) antes de que la cambiaras. Revisala en Compras.', v_purchase.number
        using errcode = 'BM409';
    end if;
    return v_purchase;
  end if;

  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'Agregá al menos un producto a la compra.' using errcode = 'P0001';
  end if;

  perform public.allow_stock_write();

  insert into public.purchases (supplier, invoice_number, notes, idempotency_key, request_hash)
  values (nullif(trim(p_supplier), ''), nullif(trim(p_invoice_number), ''), nullif(trim(p_notes), ''),
          p_idempotency_key, v_hash)
  returning * into v_purchase;

  for v_item in select value from jsonb_array_elements(p_items) loop
    v_pos := v_pos + 1;
    v_qty := (v_item->>'quantity')::numeric;
    v_cost := (v_item->>'unit_cost')::int;
    v_new_price := nullif(v_item->>'new_sale_price', '')::int;
    if v_qty is null or v_qty <= 0 then
      raise exception 'Revisá las cantidades: todas tienen que ser mayores a cero.' using errcode = 'P0001';
    end if;
    if v_cost is null or v_cost < 0 then
      raise exception 'Revisá los costos: no pueden estar vacíos ni ser negativos.' using errcode = 'P0001';
    end if;
    if v_new_price is not null and v_new_price < 0 then
      raise exception 'El precio de venta no puede ser negativo.' using errcode = 'P0001';
    end if;

    select * into v_product from public.products where id = (v_item->>'product_id')::uuid for update;
    if not found then
      raise exception 'Uno de los productos ya no existe.' using errcode = 'P0001';
    end if;

    v_line := round(v_qty * v_cost);
    v_total := v_total + v_line;

    if v_product.sold_by_load then
      -- Por carga: no hay stock; la compra se suma a la carga abierta (misma pila).
      v_load := public.open_load(v_product.id);
      update public.products set sale_price = coalesce(v_new_price, sale_price) where id = v_product.id;
      insert into public.purchase_items (
        purchase_id, position, product_id, product_name, unit, quantity, unit_cost, line_total, new_sale_price, load_id
      ) values (
        v_purchase.id, v_pos, v_product.id, v_product.name, 'carga', v_qty, v_cost, v_line, v_new_price, v_load
      );
    else
      v_new_avg := round(
        ((v_product.stock * v_product.avg_cost) + (v_qty * v_cost)) / (v_product.stock + v_qty));

      update public.products set
        stock = stock + v_qty,
        avg_cost = v_new_avg,
        sale_price = coalesce(v_new_price, sale_price)
      where id = v_product.id;

      insert into public.purchase_items (
        purchase_id, position, product_id, product_name, unit, quantity, unit_cost, line_total, new_sale_price
      ) values (
        v_purchase.id, v_pos, v_product.id, v_product.name, v_product.unit, v_qty, v_cost, v_line, v_new_price
      );

      insert into public.stock_movements (
        product_id, movement_type, quantity, stock_before, stock_after,
        unit_cost, avg_cost_before, avg_cost_after, unit_price, purchase_id
      ) values (
        v_product.id, 'compra', v_qty, v_product.stock, v_product.stock + v_qty,
        v_cost, v_product.avg_cost, v_new_avg, coalesce(v_new_price, v_product.sale_price), v_purchase.id
      );
    end if;
  end loop;

  update public.purchases set total = v_total where id = v_purchase.id returning * into v_purchase;
  return v_purchase;
end;
$$;

-- ============ Anulaciones: los productos por carga no tocan stock ============
create or replace function public.void_sale(p_sale_id uuid, p_reason text)
returns public.sales
language plpgsql security definer set search_path = '' as $$
declare
  v_sale public.sales%rowtype;
  v_item public.sale_items%rowtype;
  v_product public.products%rowtype;
  v_new_avg int;
begin
  perform public.assert_can_write();
  if nullif(trim(p_reason), '') is null then
    raise exception 'Escribí el motivo de la anulación.' using errcode = 'P0001';
  end if;

  select * into v_sale from public.sales where id = p_sale_id for update;
  if not found then raise exception 'La venta no existe.' using errcode = 'P0001'; end if;
  if v_sale.status = 'anulada' then return v_sale; end if;

  perform public.allow_stock_write();

  for v_item in select * from public.sale_items where sale_id = p_sale_id and product_id is not null loop
    select * into v_product from public.products where id = v_item.product_id for update;
    if not found or v_product.sold_by_load then continue; end if;
    v_new_avg := round(
      ((v_product.stock * v_product.avg_cost) + (v_item.quantity * v_item.unit_cost))
      / (v_product.stock + v_item.quantity));
    update public.products set stock = stock + v_item.quantity, avg_cost = v_new_avg
      where id = v_product.id;
    insert into public.stock_movements (
      product_id, movement_type, quantity, stock_before, stock_after,
      unit_cost, avg_cost_before, avg_cost_after, sale_id, reason
    ) values (
      v_product.id, 'anulacion_venta', v_item.quantity, v_product.stock, v_product.stock + v_item.quantity,
      v_item.unit_cost, v_product.avg_cost, v_new_avg, v_sale.id, trim(p_reason)
    );
  end loop;

  update public.sales set status = 'anulada', void_reason = trim(p_reason), voided_at = now()
    where id = p_sale_id returning * into v_sale;

  update public.quotes set status = 'pendiente', sale_id = null where sale_id = p_sale_id;

  return v_sale;
end;
$$;

create or replace function public.void_purchase(p_purchase_id uuid, p_reason text)
returns public.purchases
language plpgsql security definer set search_path = '' as $$
declare
  v_purchase public.purchases%rowtype;
  v_item public.purchase_items%rowtype;
  v_product public.products%rowtype;
  v_new_stock numeric(14,3);
  v_new_avg int;
begin
  perform public.assert_can_write();
  if nullif(trim(p_reason), '') is null then
    raise exception 'Escribí el motivo de la anulación.' using errcode = 'P0001';
  end if;

  select * into v_purchase from public.purchases where id = p_purchase_id for update;
  if not found then raise exception 'La compra no existe.' using errcode = 'P0001'; end if;
  if v_purchase.status = 'anulada' then return v_purchase; end if;

  -- Una compra de una carga ya cerrada no se anula: ya se usó para calcular la ganancia.
  if exists (select 1 from public.purchase_items pi join public.product_loads l on l.id = pi.load_id
             where pi.purchase_id = p_purchase_id and l.status = 'cerrada') then
    raise exception 'No se puede anular: la carga de esta compra ya se cerró.' using errcode = 'P0001';
  end if;

  perform public.allow_stock_write();

  for v_item in select * from public.purchase_items where purchase_id = p_purchase_id order by position loop
    select * into v_product from public.products where id = v_item.product_id for update;
    if v_product.sold_by_load then continue; end if;
    if v_product.stock < v_item.quantity then
      raise exception 'No se puede anular: ya se vendió parte de "%".', v_product.name using errcode = 'P0001';
    end if;
    v_new_stock := v_product.stock - v_item.quantity;
    v_new_avg := case when v_new_stock > 0
      then greatest(0, round(((v_product.stock * v_product.avg_cost) - (v_item.quantity * v_item.unit_cost)) / v_new_stock))
      else v_product.avg_cost end;

    update public.products set stock = v_new_stock, avg_cost = v_new_avg where id = v_product.id;
    insert into public.stock_movements (
      product_id, movement_type, quantity, stock_before, stock_after,
      unit_cost, avg_cost_before, avg_cost_after, purchase_id, reason
    ) values (
      v_product.id, 'anulacion_compra', -v_item.quantity, v_product.stock, v_new_stock,
      v_item.unit_cost, v_product.avg_cost, v_new_avg, v_purchase.id, trim(p_reason)
    );
  end loop;

  update public.purchases set status = 'anulada', void_reason = trim(p_reason), voided_at = now()
    where id = p_purchase_id returning * into v_purchase;
  return v_purchase;
end;
$$;

-- ============ Cerrar la carga: reparte el costo real entre sus ventas ============
-- Repetible: si ya no hay carga abierta devuelve la última cerrada.
create or replace function public.close_load(p_product_id uuid)
returns public.product_loads
language plpgsql security definer set search_path = '' as $$
declare
  v_product public.products%rowtype;
  v_load public.product_loads%rowtype;
  v_paid int;
  v_sold int;
begin
  perform public.assert_can_write();

  select * into v_product from public.products where id = p_product_id for update;
  if not found then raise exception 'El producto no existe.' using errcode = 'P0001'; end if;
  if not v_product.sold_by_load then
    raise exception 'Este producto no se vende por carga.' using errcode = 'P0001';
  end if;

  select * into v_load from public.product_loads where product_id = p_product_id and status = 'abierta' for update;
  if not found then
    select * into v_load from public.product_loads where product_id = p_product_id order by closed_at desc nulls last limit 1;
    if not found then raise exception 'Todavía no hay ninguna carga de este producto.' using errcode = 'P0001'; end if;
    return v_load;
  end if;

  v_paid := public.load_paid(v_load.id);
  v_sold := public.load_sold(v_load.id);

  if v_sold > 0 then
    -- Costo de cada línea = lo pagado × (lo que aportó esa línea / lo vendido en total).
    update public.sale_items si set unit_cost = round(
        v_paid::numeric
        * (case when sa.subtotal > 0 then si.line_total::numeric * sa.total / sa.subtotal else 0 end)
        / v_sold / si.quantity)
      from public.sales sa
      where sa.id = si.sale_id and si.load_id = v_load.id and sa.status = 'activa';

    update public.sales s set cost_total = (
        select coalesce(sum(round(i.quantity * i.unit_cost)), 0) from public.sale_items i where i.sale_id = s.id)
      where s.id in (select sale_id from public.sale_items where load_id = v_load.id);
  end if;

  update public.product_loads
    set status = 'cerrada', closed_at = now(), final_paid = v_paid, final_sold = v_sold
    where id = v_load.id
    returning * into v_load;
  return v_load;
end;
$$;

-- Estado de las cargas de un producto: la abierta (con sus números) y las últimas cerradas.
create or replace function public.load_status(p_product_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_open public.product_loads%rowtype;
begin
  if not public.is_member() then
    raise exception 'No tenés permiso para ver esto.' using errcode = '42501';
  end if;
  select * into v_open from public.product_loads where product_id = p_product_id and status = 'abierta';
  return jsonb_build_object(
    'open', case when v_open.id is null then null else jsonb_build_object(
      'id', v_open.id,
      'opened_at', v_open.opened_at,
      'paid', public.load_paid(v_open.id),
      'sold', public.load_sold(v_open.id),
      'purchases', (select count(distinct pi.purchase_id) from public.purchase_items pi join public.purchases pu on pu.id = pi.purchase_id
                    where pi.load_id = v_open.id and pu.status = 'activa'),
      'sales', (select count(distinct si.sale_id) from public.sale_items si join public.sales sa on sa.id = si.sale_id
                where si.load_id = v_open.id and sa.status = 'activa'),
      'quantity', (select coalesce(sum(si.quantity), 0) from public.sale_items si join public.sales sa on sa.id = si.sale_id
                   where si.load_id = v_open.id and sa.status = 'activa')
    ) end,
    'closed', (select coalesce(jsonb_agg(jsonb_build_object(
                  'opened_at', opened_at, 'closed_at', closed_at, 'paid', final_paid, 'sold', final_sold) order by closed_at desc), '[]'::jsonb)
               from (select * from public.product_loads where product_id = p_product_id and status = 'cerrada'
                     order by closed_at desc limit 12) t)
  );
end;
$$;

-- ============ Inicio: los productos por carga no cuentan como agotados ============
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
    select total, cost_total, payment_method,
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
        'efectivo', coalesce(sum(total) filter (where d >= v_month and payment_method = 'efectivo'), 0),
        'transferencia', coalesce(sum(total) filter (where d >= v_month and payment_method = 'transferencia'), 0),
        'qr', coalesce(sum(total) filter (where d >= v_month and payment_method = 'qr'), 0))
    ) as j
    from s
  ),
  yearly as (
    select jsonb_build_object(
      'sales', coalesce(sum(total), 0),
      'profit', coalesce(sum(total - cost_total), 0),
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
    where created_at >= v_month::timestamp at time zone 'America/Asuncion'
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

revoke all on function public.open_load(uuid), public.load_paid(uuid), public.load_sold(uuid) from public, anon, authenticated;
revoke all on function public.close_load(uuid), public.load_status(uuid) from public, anon;
grant execute on function public.close_load(uuid), public.load_status(uuid) to authenticated;
-- create_sale, create_purchase, void_* y dashboard_summary conservan sus permisos (create or replace).

-- ============ Unidad "palada" (se vende por palada de la cargadora) ============
alter table public.products drop constraint if exists products_unit_ok;
alter table public.products add constraint products_unit_ok
  check (unit in ('unidad', 'bolsa', 'metro', 'kg', 'm²', 'm³', 'lt', 'barra', 'caja', 'rollo', 'carga', 'camión', 'palada'));
