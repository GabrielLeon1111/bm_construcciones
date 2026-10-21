-- =====================================================================
--  Idempotencia estricta + arreglo del guardia de stock
--
--  1. Toda operación que registra algo (venta, compra, presupuesto nuevo
--     o editado, ajuste de stock) exige una clave de operación. Si llega
--     dos veces la misma clave (doble toque, reintento tras un corte de
--     internet) se devuelve lo que ya se registró, sin duplicar.
--     * Un candado por clave (pg_advisory_xact_lock) evita la carrera de
--       dos pedidos simultáneos.
--     * Se guarda un hash del pedido: la misma clave con datos distintos
--       se rechaza con el código BM409 en vez de devolver otra cosa.
--  2. Un presupuesto solo se puede convertir en venta una vez.
--  3. cancel_quote se puede repetir sin error.
--  4. El trigger products_guard_stock rechazaba TODO cambio de stock
--     porque ninguna función activaba app.stock_write. Ahora las
--     funciones lo activan (solo dentro de su transacción).
--  5. Se cierran los permisos que no habían quedado aplicados
--     (anon con acceso a tablas y funciones, TRUNCATE, etc.).
-- =====================================================================

-- ============ Columnas ============
alter table public.sales add column request_hash text;
alter table public.purchases add column request_hash text;
alter table public.quotes
  add column request_hash text,
  add column last_edit_key uuid,
  add column last_edit_hash text;
alter table public.stock_movements
  add column idempotency_key uuid unique,
  add column request_hash text;

-- ============ Helpers ============
-- Exige la clave y toma un candado por (tipo, clave) hasta el fin de la transacción.
create or replace function public.idem_lock(p_scope text, p_key uuid)
returns void language plpgsql set search_path = '' as $$
begin
  if p_key is null then
    raise exception 'Falta la clave de la operación. Actualizá la app.' using errcode = 'P0001';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_scope || ':' || p_key::text, 0));
end;
$$;

-- Habilita el cambio de stock (lo controla products_guard_stock) solo en esta transacción.
create or replace function public.allow_stock_write()
returns void language sql set search_path = '' as $$
  select set_config('app.stock_write', 'on', true);
$$;

-- ============ create_sale ============
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

  -- Un presupuesto se convierte en venta una sola vez.
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
    v_desc := nullif(trim(v_item->>'description'), '');
    v_unit := coalesce(nullif(trim(v_item->>'unit'), ''), 'unidad');

    if nullif(v_item->>'product_id', '') is not null then
      select * into v_product from public.products
        where id = (v_item->>'product_id')::uuid for update;
      if not found then
        raise exception 'Uno de los productos ya no existe.' using errcode = 'P0001';
      end if;
      if v_product.stock < v_qty then
        raise exception 'No hay stock suficiente de "%" (quedan %).',
          v_product.name, trim(trailing '.' from trim(trailing '0' from v_product.stock::text))
          using errcode = 'P0001';
      end if;
      v_cost := v_product.avg_cost;
      v_desc := coalesce(v_desc, v_product.name);
      v_unit := v_product.unit;

      update public.products set stock = stock - v_qty where id = v_product.id;

      insert into public.stock_movements (
        product_id, movement_type, quantity, stock_before, stock_after,
        unit_cost, avg_cost_before, avg_cost_after, unit_price, sale_id
      ) values (
        v_product.id, 'venta', -v_qty, v_product.stock, v_product.stock - v_qty,
        v_product.avg_cost, v_product.avg_cost, v_product.avg_cost, v_price, v_sale.id
      );
    elsif v_desc is null then
      raise exception 'Cada línea necesita un producto o una descripción.' using errcode = 'P0001';
    end if;

    v_line := round(v_qty * v_price);
    v_subtotal := v_subtotal + v_line;
    v_cost_total := v_cost_total + round(v_qty * v_cost);

    insert into public.sale_items (
      sale_id, position, product_id, description, unit, quantity,
      unit_price, unit_cost, is_gift, line_total
    ) values (
      v_sale.id, v_pos, v_product.id, v_desc, v_unit, v_qty,
      v_price, v_cost, v_gift, v_line
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

-- ============ create_purchase ============
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

    v_new_avg := round(
      ((v_product.stock * v_product.avg_cost) + (v_qty * v_cost)) / (v_product.stock + v_qty));
    v_line := round(v_qty * v_cost);
    v_total := v_total + v_line;

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
  end loop;

  update public.purchases set total = v_total where id = v_purchase.id returning * into v_purchase;
  return v_purchase;
end;
$$;

-- ============ save_quote ============
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
    -- Reintento de la misma edición: no se crea otra versión.
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

    v_line := round(v_qty * v_price);
    v_subtotal := v_subtotal + v_line;

    insert into public.quote_items (
      quote_id, version, position, product_id, description, unit, quantity, unit_price, is_gift, line_total
    ) values (
      v_quote.id, v_quote.version, v_pos, v_product.id, v_desc, v_unit, v_qty, v_price, v_gift, v_line
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

-- ============ adjust_stock (ahora con clave) ============
-- Se agrega como función nueva de 5 parámetros, sin borrar la vieja de 4
-- (que queda sin permiso de ejecución, ver PERMISOS). Así no hace falta
-- ninguna operación destructiva.
create or replace function public.adjust_stock(
  p_product_id uuid,
  p_new_stock numeric,
  p_reason text,
  p_unit_cost integer,
  p_idempotency_key uuid
)
returns public.stock_movements
language plpgsql security definer set search_path = '' as $$
declare
  v_product public.products%rowtype;
  v_diff numeric(14,3);
  v_new_avg int;
  v_movement public.stock_movements%rowtype;
  v_hash text;
begin
  perform public.assert_can_write();
  perform public.idem_lock('adjust', p_idempotency_key);

  v_hash := md5(jsonb_build_object(
    'product', p_product_id, 'stock', p_new_stock, 'reason', nullif(trim(p_reason), ''), 'cost', p_unit_cost)::text);

  select * into v_movement from public.stock_movements where idempotency_key = p_idempotency_key;
  if found then
    if v_movement.request_hash is distinct from v_hash then
      raise exception 'Este ajuste ya se había registrado con otros datos. Revisá el historial del producto.'
        using errcode = 'BM409';
    end if;
    return v_movement;
  end if;

  if p_new_stock is null or p_new_stock < 0 then
    raise exception 'El stock no puede ser negativo.' using errcode = 'P0001';
  end if;
  if nullif(trim(p_reason), '') is null then
    raise exception 'Escribí el motivo del ajuste.' using errcode = 'P0001';
  end if;
  if p_unit_cost is not null and p_unit_cost < 0 then
    raise exception 'El costo no puede ser negativo.' using errcode = 'P0001';
  end if;

  select * into v_product from public.products where id = p_product_id for update;
  if not found then raise exception 'El producto no existe.' using errcode = 'P0001'; end if;

  v_diff := p_new_stock - v_product.stock;
  if v_diff = 0 then
    raise exception 'El stock ya es ese. No hay nada que ajustar.' using errcode = 'P0001';
  end if;

  v_new_avg := case when v_diff > 0 and p_unit_cost is not null
    then round(((v_product.stock * v_product.avg_cost) + (v_diff * p_unit_cost)) / p_new_stock)
    else v_product.avg_cost end;

  perform public.allow_stock_write();
  update public.products set stock = p_new_stock, avg_cost = v_new_avg where id = v_product.id;

  insert into public.stock_movements (
    product_id, movement_type, quantity, stock_before, stock_after,
    unit_cost, avg_cost_before, avg_cost_after, reason, idempotency_key, request_hash
  ) values (
    v_product.id, 'ajuste', v_diff, v_product.stock, p_new_stock,
    coalesce(p_unit_cost, v_product.avg_cost), v_product.avg_cost, v_new_avg, trim(p_reason),
    p_idempotency_key, v_hash
  ) returning * into v_movement;

  return v_movement;
end;
$$;

-- ============ Anulaciones (ya eran repetibles; faltaba habilitar el stock) ============
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
    if not found then continue; end if;
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

  perform public.allow_stock_write();

  for v_item in select * from public.purchase_items where purchase_id = p_purchase_id order by position loop
    select * into v_product from public.products where id = v_item.product_id for update;
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

-- ============ cancel_quote: repetible ============
create or replace function public.cancel_quote(p_quote_id uuid)
returns public.quotes
language plpgsql security definer set search_path = '' as $$
declare
  v_quote public.quotes%rowtype;
begin
  perform public.assert_can_write();
  select * into v_quote from public.quotes where id = p_quote_id for update;
  if not found then raise exception 'El presupuesto no existe.' using errcode = 'P0001'; end if;
  if v_quote.status = 'anulado' then return v_quote; end if;
  if v_quote.status <> 'pendiente' then
    raise exception 'Solo se pueden anular presupuestos pendientes.' using errcode = 'P0001';
  end if;
  update public.quotes set status = 'anulado' where id = p_quote_id returning * into v_quote;
  return v_quote;
end;
$$;

-- =====================================================================
--  PERMISOS
-- =====================================================================
-- Funciones: nadie por defecto; authenticated solo las que llama la app
-- (y is_member/license_ok, que usan las políticas RLS).
revoke all on all functions in schema public from public, anon, authenticated;
grant execute on function
  public.is_member(),
  public.license_ok(),
  public.create_sale(jsonb, text, uuid, integer, text, uuid, uuid),
  public.void_sale(uuid, text),
  public.create_purchase(jsonb, text, text, text, uuid),
  public.void_purchase(uuid, text),
  public.adjust_stock(uuid, numeric, text, integer, uuid),
  public.save_quote(jsonb, uuid, uuid, integer, text, date, uuid),
  public.cancel_quote(uuid),
  public.dashboard_summary(),
  public.sales_report(date, date)
  to authenticated;

-- Tablas: anon no toca nada.
revoke all on all tables in schema public from anon;
-- Los movimientos solo se escriben con las funciones de arriba.
revoke insert, update, delete, truncate, references, trigger on
  public.app_members, public.app_license, public.purchases, public.purchase_items,
  public.quotes, public.quote_items, public.sales, public.sale_items, public.stock_movements,
  public.v_sale_lines
  from authenticated;
revoke delete, insert, truncate, references, trigger on public.business_settings from authenticated;
revoke truncate, references, trigger on public.products, public.clients from authenticated;

alter default privileges in schema public revoke all on tables from anon;
alter default privileges in schema public revoke all on functions from public, anon;
