-- Día en que se compró (el de la factura). Puede ser anterior al día en que se carga en el sistema.
alter table public.purchases add column if not exists purchased_on date not null default current_date;

alter table public.purchases drop constraint if exists purchases_purchased_on_ok;
alter table public.purchases add constraint purchases_purchased_on_ok
  check (purchased_on >= date '2000-01-01' and purchased_on <= (created_at at time zone 'America/Asuncion')::date + 1);

-- Las compras ya cargadas: el día de compra es el día en que se registraron.
update public.purchases set purchased_on = (created_at at time zone 'America/Asuncion')::date
where purchased_on <> (created_at at time zone 'America/Asuncion')::date;

-- Nueva versión con el día de compra (obligatorio en esta firma para no confundirse con la anterior).
create or replace function public.create_purchase(
  p_items jsonb,
  p_supplier text,
  p_invoice_number text,
  p_notes text,
  p_idempotency_key uuid,
  p_purchased_on date
) returns public.purchases
language plpgsql
security definer
set search_path to ''
as $function$
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
  v_hoy date := (now() at time zone 'America/Asuncion')::date;
  v_dia date := coalesce(p_purchased_on, (now() at time zone 'America/Asuncion')::date);
begin
  perform public.assert_can_write();
  perform public.idem_lock('purchase', p_idempotency_key);

  v_hash := md5(jsonb_build_object(
    'items', p_items, 'supplier', nullif(trim(p_supplier), ''),
    'invoice', nullif(trim(p_invoice_number), ''), 'notes', nullif(trim(p_notes), ''),
    'dia', v_dia)::text);

  select * into v_purchase from public.purchases where idempotency_key = p_idempotency_key;
  if found then
    if v_purchase.request_hash is distinct from v_hash then
      raise exception 'Esta compra ya se había registrado (N° %) antes de que la cambiaras. Revisala en Compras.', v_purchase.number
        using errcode = 'BM409';
    end if;
    return v_purchase;
  end if;

  if v_dia > v_hoy then
    raise exception 'El día de la compra no puede ser posterior a hoy.' using errcode = 'P0001';
  end if;
  if v_dia < date '2000-01-01' then
    raise exception 'Revisá el día de la compra.' using errcode = 'P0001';
  end if;

  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'Agregá al menos un producto a la compra.' using errcode = 'P0001';
  end if;

  perform public.allow_stock_write();

  insert into public.purchases (supplier, invoice_number, notes, idempotency_key, request_hash, purchased_on)
  values (nullif(trim(p_supplier), ''), nullif(trim(p_invoice_number), ''), nullif(trim(p_notes), ''),
          p_idempotency_key, v_hash, v_dia)
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
$function$;

revoke all on function public.create_purchase(jsonb, text, text, text, uuid, date) from public, anon;
grant execute on function public.create_purchase(jsonb, text, text, text, uuid, date) to authenticated;
