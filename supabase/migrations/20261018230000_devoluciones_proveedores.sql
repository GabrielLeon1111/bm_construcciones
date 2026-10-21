-- =====================================================================
--  1. Devoluciones parciales de ventas: el cliente devuelve parte del
--     material. Vuelve el stock y ese monto deja de contar en ventas y
--     ganancias (la venta queda en el historial con lo devuelto).
--     La anulación completa ya existía (void_sale); ahora respeta lo
--     que ya se había devuelto.
--  2. Proveedores guardados para reutilizar en las compras.
--  3. "Precio por línea" (price_is_total): para arena y demás productos
--     por carga se escribe cuánto se cobra por esa línea (1/2 palada =
--     Gs. 300.000), no un precio por unidad. Así sale como el talonario.
--  Requiere 20261018220000_productos_por_carga.sql.
-- =====================================================================

-- ============ Columnas ============
alter table public.sale_items
  add column if not exists returned_qty numeric(14,3) not null default 0,
  add column if not exists price_is_total boolean not null default false;
alter table public.sale_items
  add constraint sale_items_returned_ok check (returned_qty >= 0 and returned_qty <= quantity);
alter table public.quote_items add column if not exists price_is_total boolean not null default false;
alter table public.sales
  add column if not exists returned_amount integer not null default 0,
  add column if not exists returned_cost integer not null default 0;
alter table public.sales
  add constraint sales_returned_ok check (returned_amount >= 0 and returned_amount <= total and returned_cost >= 0);

-- ============ Devoluciones ============
create table if not exists public.sale_returns (
  id uuid primary key default gen_random_uuid(),
  sale_id uuid not null references public.sales(id) on delete restrict,
  reason text not null check (public.texto_ok(reason, 150, 3)),
  amount integer not null check (public.monto_ok(amount)),
  cost integer not null default 0 check (public.monto_ok(cost)),
  idempotency_key uuid unique,
  request_hash text,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now()
);
create table if not exists public.sale_return_items (
  id uuid primary key default gen_random_uuid(),
  return_id uuid not null references public.sale_returns(id) on delete cascade,
  sale_item_id uuid not null references public.sale_items(id) on delete restrict,
  quantity numeric(14,3) not null check (public.cantidad_ok(quantity)),
  amount integer not null check (public.monto_ok(amount)),
  cost integer not null default 0 check (public.monto_ok(cost))
);
create index if not exists sale_returns_sale_idx on public.sale_returns (sale_id);
create index if not exists sale_return_items_return_idx on public.sale_return_items (return_id);

alter table public.sale_returns enable row level security;
alter table public.sale_return_items enable row level security;
create policy members_read on public.sale_returns for select to authenticated using ((select public.is_member()));
create policy members_read on public.sale_return_items for select to authenticated using ((select public.is_member()));
grant select on public.sale_returns, public.sale_return_items to authenticated;

-- ============ Proveedores ============
create table if not exists public.suppliers (
  id uuid primary key default gen_random_uuid(),
  name text not null check (public.texto_ok(name, 80, 2)),
  phone text check (phone is null or (char_length(phone) <= 20 and phone ~ '^\+?[0-9 ()-]+$')),
  ruc text check (ruc is null or (char_length(ruc) <= 15 and ruc ~ '^[0-9.]{5,11}(-[0-9])?$')),
  notes text check (public.texto_largo_ok(notes, 300)),
  created_at timestamptz not null default now()
);
create unique index if not exists suppliers_name_unique on public.suppliers (lower(name));
alter table public.suppliers enable row level security;
create policy members_all on public.suppliers for all to authenticated
  using ((select public.is_member())) with check ((select public.is_member()));
grant select, insert, update, delete on public.suppliers to authenticated;

-- Los que ya se usaron en compras quedan guardados.
insert into public.suppliers (name)
select distinct on (lower(trim(supplier))) trim(supplier) from public.purchases
where nullif(trim(supplier), '') is not null
on conflict do nothing;

-- ============ Lo vendido en una carga, descontando devoluciones ============
create or replace function public.load_sold(p_load_id uuid)
returns integer language sql stable security definer set search_path = '' as $$
  select coalesce(sum(case when sa.subtotal > 0 and si.quantity > 0
      then round(si.line_total::numeric * sa.total / sa.subtotal * (si.quantity - si.returned_qty) / si.quantity) else 0 end), 0)::int
  from public.sale_items si join public.sales sa on sa.id = si.sale_id
  where si.load_id = p_load_id and sa.status = 'activa';
$$;

-- ============ create_sale: precio por línea ============
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
  v_por_linea boolean;
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
    v_por_linea := coalesce((v_item->>'price_is_total')::boolean, false) and not v_gift;
    v_price := case when v_gift then 0 else coalesce((v_item->>'unit_price')::int, 0) end;
    if v_qty is null or v_qty <= 0 then
      raise exception 'Revisá las cantidades: todas tienen que ser mayores a cero.' using errcode = 'P0001';
    end if;
    if v_price < 0 then
      raise exception 'El precio no puede ser negativo.' using errcode = 'P0001';
    end if;
    -- Precio por línea: lo escrito es lo que se cobra por toda la línea.
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

-- ============ save_quote: precio por línea ============
create or replace function public.save_quote(
  p_items jsonb,
  p_quote_id uuid default null,
  p_client_id uuid default null,
  p_discount integer default 0,
  p_notes text default null,
  p_valid_until date default null,
  p_idempotency_key uuid default null
)
returns public.quotes
language plpgsql security definer set search_path = '' as $$
declare
  v_quote public.quotes%rowtype;
  v_client_name text;
  v_product public.products%rowtype;
  v_item jsonb;
  v_pos int := 0;
  v_qty numeric(14,3);
  v_price int;
  v_gift boolean;
  v_por_linea boolean;
  v_line int;
  v_subtotal int := 0;
  v_desc text;
  v_unit text;
  v_hash text;
begin
  perform public.assert_can_write();
  perform public.idem_lock('quote', p_idempotency_key);

  v_hash := md5(jsonb_build_object(
    'items', p_items, 'client', p_client_id, 'discount', coalesce(p_discount, 0),
    'notes', nullif(trim(p_notes), ''), 'valid_until', p_valid_until)::text);

  if p_quote_id is null then
    select * into v_quote from public.quotes where idempotency_key = p_idempotency_key;
    if found then
      if v_quote.request_hash is distinct from v_hash then
        raise exception 'Este presupuesto ya se había guardado (N° %) antes de que lo cambiaras. Abrilo y editalo desde Presupuestos.', v_quote.number
          using errcode = 'BM409';
      end if;
      return v_quote;
    end if;
  else
    select * into v_quote from public.quotes where id = p_quote_id for update;
    if not found then raise exception 'El presupuesto no existe.' using errcode = 'P0001'; end if;
    if v_quote.last_edit_key = p_idempotency_key then
      if v_quote.last_edit_hash is distinct from v_hash then
        raise exception 'Este cambio del presupuesto N° % ya se había guardado. Volvé a abrirlo para seguir editando.', v_quote.number
          using errcode = 'BM409';
      end if;
      return v_quote;
    end if;
    if v_quote.status <> 'pendiente' then
      raise exception 'Este presupuesto ya fue vendido o anulado; no se puede editar.' using errcode = 'P0001';
    end if;
  end if;

  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'Agregá al menos un producto al presupuesto.' using errcode = 'P0001';
  end if;
  if coalesce(p_discount, 0) < 0 then
    raise exception 'El descuento no puede ser negativo.' using errcode = 'P0001';
  end if;

  if p_client_id is not null then
    select full_name into v_client_name from public.clients where id = p_client_id;
  end if;

  if p_quote_id is null then
    insert into public.quotes (client_id, client_name, notes, valid_until, idempotency_key, request_hash)
    values (p_client_id, v_client_name, nullif(trim(p_notes), ''), p_valid_until, p_idempotency_key, v_hash)
    returning * into v_quote;
  else
    update public.quotes set client_id = p_client_id, client_name = v_client_name,
      notes = nullif(trim(p_notes), ''), valid_until = p_valid_until, version = version + 1,
      last_edit_key = p_idempotency_key, last_edit_hash = v_hash
      where id = p_quote_id
      returning * into v_quote;
  end if;

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
    v_desc := nullif(trim(v_item->>'description'), '');
    v_unit := coalesce(nullif(trim(v_item->>'unit'), ''), 'unidad');

    if nullif(v_item->>'product_id', '') is not null then
      select * into v_product from public.products where id = (v_item->>'product_id')::uuid;
      if found then
        v_desc := coalesce(v_desc, v_product.name);
        v_unit := v_product.unit;
      end if;
    end if;
    if v_desc is null then
      raise exception 'Cada línea necesita un producto o una descripción.' using errcode = 'P0001';
    end if;

    v_line := case when v_por_linea then v_price else round(v_qty * v_price) end;
    v_subtotal := v_subtotal + v_line;

    insert into public.quote_items (
      quote_id, version, position, product_id, description, unit, quantity, unit_price, is_gift, line_total, price_is_total
    ) values (
      v_quote.id, v_quote.version, v_pos, v_product.id, v_desc, v_unit, v_qty, v_price, v_gift, v_line, v_por_linea
    );
    v_product := null;
  end loop;

  if coalesce(p_discount, 0) > v_subtotal then
    raise exception 'El descuento no puede ser mayor al total.' using errcode = 'P0001';
  end if;

  update public.quotes set subtotal = v_subtotal, discount = coalesce(p_discount, 0),
    total = v_subtotal - coalesce(p_discount, 0)
    where id = v_quote.id returning * into v_quote;
  return v_quote;
end;
$$;

-- ============ Devolución parcial ============
-- p_items: [{ "sale_item_id": uuid, "quantity": numeric }]
create or replace function public.return_sale(
  p_sale_id uuid,
  p_items jsonb,
  p_reason text,
  p_idempotency_key uuid default null
)
returns public.sale_returns
language plpgsql security definer set search_path = '' as $$
declare
  v_sale public.sales%rowtype;
  v_si public.sale_items%rowtype;
  v_product public.products%rowtype;
  v_ret public.sale_returns%rowtype;
  v_item jsonb;
  v_qty numeric(14,3);
  v_amount int;
  v_cost int;
  v_total_amount int := 0;
  v_total_cost int := 0;
  v_new_avg int;
  v_hash text;
begin
  perform public.assert_can_write();
  perform public.idem_lock('return', p_idempotency_key);

  v_hash := md5(jsonb_build_object('sale', p_sale_id, 'items', p_items, 'reason', nullif(trim(p_reason), ''))::text);

  select * into v_ret from public.sale_returns where idempotency_key = p_idempotency_key;
  if found then
    if v_ret.request_hash is distinct from v_hash then
      raise exception 'Esta devolución ya se había registrado con otros datos. Revisá la venta.' using errcode = 'BM409';
    end if;
    return v_ret;
  end if;

  if nullif(trim(p_reason), '') is null then
    raise exception 'Escribí el motivo de la devolución.' using errcode = 'P0001';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'Elegí qué se devuelve.' using errcode = 'P0001';
  end if;

  select * into v_sale from public.sales where id = p_sale_id for update;
  if not found then raise exception 'La venta no existe.' using errcode = 'P0001'; end if;
  if v_sale.status <> 'activa' then
    raise exception 'Esta venta está anulada; no se puede devolver.' using errcode = 'P0001';
  end if;

  insert into public.sale_returns (sale_id, reason, amount, cost, idempotency_key, request_hash)
  values (p_sale_id, trim(p_reason), 0, 0, p_idempotency_key, v_hash)
  returning * into v_ret;

  perform public.allow_stock_write();

  for v_item in select value from jsonb_array_elements(p_items) loop
    v_qty := (v_item->>'quantity')::numeric;
    if v_qty is null or v_qty <= 0 then continue; end if;

    select * into v_si from public.sale_items
      where id = (v_item->>'sale_item_id')::uuid and sale_id = p_sale_id for update;
    if not found then raise exception 'Uno de los materiales no es de esta venta.' using errcode = 'P0001'; end if;
    if v_qty > v_si.quantity - v_si.returned_qty + 0.0001 then
      raise exception 'De "%" se pueden devolver como máximo %.', v_si.description,
        trim(trailing '.' from trim(trailing '0' from (v_si.quantity - v_si.returned_qty)::text)) using errcode = 'P0001';
    end if;

    -- Lo que se devuelve: parte proporcional de la línea, con el descuento repartido.
    v_amount := case when v_sale.subtotal > 0
      then round(v_si.line_total::numeric * v_sale.total / v_sale.subtotal * v_qty / v_si.quantity) else 0 end;
    v_cost := round(v_qty * v_si.unit_cost);

    update public.sale_items set returned_qty = returned_qty + v_qty where id = v_si.id;

    -- El material vuelve al stock (los productos por carga no tienen stock).
    if v_si.product_id is not null then
      select * into v_product from public.products where id = v_si.product_id for update;
      if found and not v_product.sold_by_load then
        v_new_avg := round(((v_product.stock * v_product.avg_cost) + (v_qty * v_si.unit_cost)) / (v_product.stock + v_qty));
        update public.products set stock = stock + v_qty, avg_cost = v_new_avg where id = v_product.id;
        insert into public.stock_movements (
          product_id, movement_type, quantity, stock_before, stock_after,
          unit_cost, avg_cost_before, avg_cost_after, sale_id, reason
        ) values (
          v_product.id, 'anulacion_venta', v_qty, v_product.stock, v_product.stock + v_qty,
          v_si.unit_cost, v_product.avg_cost, v_new_avg, p_sale_id, 'Devolución: ' || trim(p_reason)
        );
      end if;
    end if;

    insert into public.sale_return_items (return_id, sale_item_id, quantity, amount, cost)
    values (v_ret.id, v_si.id, v_qty, v_amount, v_cost);

    v_total_amount := v_total_amount + v_amount;
    v_total_cost := v_total_cost + v_cost;
  end loop;

  if v_total_amount = 0 and v_total_cost = 0 and not exists (select 1 from public.sale_return_items where return_id = v_ret.id) then
    raise exception 'Elegí cuánto se devuelve de al menos un material.' using errcode = 'P0001';
  end if;

  update public.sales set
    returned_amount = least(total, returned_amount + v_total_amount),
    returned_cost = returned_cost + v_total_cost
  where id = p_sale_id;

  update public.sale_returns set amount = v_total_amount, cost = v_total_cost where id = v_ret.id returning * into v_ret;
  return v_ret;
end;
$$;

-- ============ Anular venta: solo vuelve lo que no se había devuelto ============
create or replace function public.void_sale(p_sale_id uuid, p_reason text)
returns public.sales
language plpgsql security definer set search_path = '' as $$
declare
  v_sale public.sales%rowtype;
  v_item public.sale_items%rowtype;
  v_product public.products%rowtype;
  v_qty numeric(14,3);
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
    v_qty := v_item.quantity - v_item.returned_qty;
    if v_qty <= 0 then continue; end if;
    select * into v_product from public.products where id = v_item.product_id for update;
    if not found or v_product.sold_by_load then continue; end if;
    v_new_avg := round(
      ((v_product.stock * v_product.avg_cost) + (v_qty * v_item.unit_cost))
      / (v_product.stock + v_qty));
    update public.products set stock = stock + v_qty, avg_cost = v_new_avg
      where id = v_product.id;
    insert into public.stock_movements (
      product_id, movement_type, quantity, stock_before, stock_after,
      unit_cost, avg_cost_before, avg_cost_after, sale_id, reason
    ) values (
      v_product.id, 'anulacion_venta', v_qty, v_product.stock, v_product.stock + v_qty,
      v_item.unit_cost, v_product.avg_cost, v_new_avg, v_sale.id, trim(p_reason)
    );
  end loop;

  update public.sales set status = 'anulada', void_reason = trim(p_reason), voided_at = now()
    where id = p_sale_id returning * into v_sale;

  update public.quotes set status = 'pendiente', sale_id = null where sale_id = p_sale_id;

  return v_sale;
end;
$$;

-- ============ Cerrar carga: respeta las devoluciones ============
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
    -- Costo de cada línea = lo pagado × lo que aportó (sin lo devuelto) / lo vendido.
    -- Se reparte sobre lo que el cliente se quedó.
    update public.sale_items si set unit_cost = case when si.quantity - si.returned_qty > 0 then round(
        v_paid::numeric
        * (case when sa.subtotal > 0 then si.line_total::numeric * sa.total / sa.subtotal * (si.quantity - si.returned_qty) / si.quantity else 0 end)
        / v_sold / (si.quantity - si.returned_qty)) else 0 end
      from public.sales sa
      where sa.id = si.sale_id and si.load_id = v_load.id and sa.status = 'activa';

    update public.sales s set
        cost_total = (select coalesce(sum(round(i.quantity * i.unit_cost)), 0) from public.sale_items i where i.sale_id = s.id),
        returned_cost = (select coalesce(sum(round(i.returned_qty * i.unit_cost)), 0) from public.sale_items i where i.sale_id = s.id)
      where s.id in (select sale_id from public.sale_items where load_id = v_load.id);
  end if;

  update public.product_loads
    set status = 'cerrada', closed_at = now(), final_paid = v_paid, final_sold = v_sold
    where id = v_load.id
    returning * into v_load;
  return v_load;
end;
$$;

-- ============ Reportes: lo devuelto no cuenta ============
create or replace view public.v_sale_lines as
 select si.id,
    s.id as sale_id,
    s.number as sale_number,
    s.created_at,
    s.payment_method,
    s.client_id,
    si.product_id,
    si.description,
    coalesce(p.category, 'Sin categoría'::text) as category,
    si.unit,
    (si.quantity - si.returned_qty)::numeric(14,3) as quantity,
    si.unit_price,
    si.unit_cost,
    si.is_gift,
    si.line_total,
    case when s.subtotal > 0 and si.quantity > 0
      then round(si.line_total::numeric * s.total::numeric / s.subtotal::numeric * (si.quantity - si.returned_qty) / si.quantity)::integer
      else 0 end as net_revenue,
    round((si.quantity - si.returned_qty) * si.unit_cost::numeric)::integer as cost
   from public.sale_items si
     join public.sales s on s.id = si.sale_id
     left join public.products p on p.id = si.product_id
  where s.status = 'activa'::text;

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
      'efectivo', coalesce(sum(total - returned_amount) filter (where payment_method = 'efectivo'), 0),
      'transferencia', coalesce(sum(total - returned_amount) filter (where payment_method = 'transferencia'), 0),
      'qr', coalesce(sum(total - returned_amount) filter (where payment_method = 'qr'), 0)),
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
    -- Ventas netas: sin lo devuelto.
    select (total - returned_amount) as total, (cost_total - returned_cost) as cost_total, payment_method,
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

revoke all on function public.return_sale(uuid, jsonb, text, uuid) from public, anon;
grant execute on function public.return_sale(uuid, jsonb, text, uuid) to authenticated;
