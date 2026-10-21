-- =====================================================================
--  Validación en la base (última barrera)
--  La app ya valida cada campo, pero alguien podría llamar a la API
--  directamente con la clave pública. Estas reglas hacen que la base
--  rechace cualquier dato fuera de rango, sin importar de dónde venga.
--
--  Inyección SQL: no hay SQL dinámico en ninguna función (ni EXECUTE ni
--  format); todo dato entra como parámetro tipado por PostgREST / plpgsql.
--  Estas reglas cubren el resto: largos, formatos, montos y caracteres
--  de control.
--
--  Mismos límites que lib/utils/validacion.dart.
-- =====================================================================

-- Texto de una línea: sin caracteres de control.
create or replace function public.texto_ok(t text, max_len int, min_len int default 1)
returns boolean language sql immutable set search_path = '' as $$
  select t is null or (char_length(t) between min_len and max_len and t !~ '[[:cntrl:]]');
$$;

-- Texto de varias líneas: se permiten saltos de línea, nada más de control.
create or replace function public.texto_largo_ok(t text, max_len int)
returns boolean language sql immutable set search_path = '' as $$
  select t is null or (char_length(t) <= max_len and translate(t, E'\n', '') !~ '[[:cntrl:]]');
$$;

create or replace function public.monto_ok(m bigint)
returns boolean language sql immutable set search_path = '' as $$
  select m is null or m between 0 and 999999999;
$$;

create or replace function public.cantidad_ok(q numeric)
returns boolean language sql immutable set search_path = '' as $$
  select q is null or (q > 0 and q <= 100000);
$$;

-- ============ Productos ============
alter table public.products
  add constraint products_name_ok check (public.texto_ok(name, 80, 2)),
  add constraint products_category_ok check (public.texto_ok(category, 40)),
  add constraint products_brand_ok check (public.texto_ok(brand, 40)),
  add constraint products_unit_ok check (unit in ('unidad', 'bolsa', 'metro', 'kg', 'm²', 'm³', 'lt', 'barra', 'caja', 'rollo', 'carga', 'camión')),
  add constraint products_notes_ok check (public.texto_largo_ok(notes, 300)),
  add constraint products_sale_price_ok check (public.monto_ok(sale_price)),
  add constraint products_avg_cost_ok check (public.monto_ok(avg_cost)),
  add constraint products_min_stock_ok check (min_stock <= 100000),
  add constraint products_stock_ok check (stock <= 99999999);

-- ============ Clientes ============
alter table public.clients
  add constraint clients_full_name_ok check (public.texto_ok(full_name, 80, 2)),
  add constraint clients_phone_ok check (phone is null or (char_length(phone) <= 20 and phone ~ '^\+?[0-9 ()-]+$')),
  add constraint clients_document_ok check (document is null or (char_length(document) <= 15 and document ~ '^[0-9.]{5,11}(-[0-9])?$')),
  add constraint clients_address_ok check (public.texto_ok(address, 150)),
  add constraint clients_notes_ok check (public.texto_largo_ok(notes, 300));

-- ============ Ventas ============
alter table public.sales
  add constraint sales_client_name_ok check (public.texto_ok(client_name, 80)),
  add constraint sales_client_phone_ok check (public.texto_ok(client_phone, 20)),
  add constraint sales_client_document_ok check (public.texto_ok(client_document, 15)),
  add constraint sales_client_address_ok check (public.texto_ok(client_address, 150)),
  add constraint sales_notes_ok check (public.texto_largo_ok(notes, 300)),
  add constraint sales_void_reason_ok check (public.texto_ok(void_reason, 150)),
  add constraint sales_amounts_ok check (
    public.monto_ok(subtotal) and public.monto_ok(discount) and public.monto_ok(total)
    and public.monto_ok(cost_total) and discount <= subtotal);

alter table public.sale_items
  add constraint sale_items_description_ok check (public.texto_ok(description, 120)),
  add constraint sale_items_unit_ok check (public.texto_ok(unit, 20)),
  add constraint sale_items_quantity_ok check (public.cantidad_ok(quantity)),
  add constraint sale_items_amounts_ok check (public.monto_ok(unit_price) and public.monto_ok(unit_cost) and public.monto_ok(line_total));

-- ============ Compras ============
alter table public.purchases
  add constraint purchases_supplier_ok check (public.texto_ok(supplier, 80)),
  add constraint purchases_invoice_ok check (invoice_number is null or (char_length(invoice_number) <= 30 and invoice_number ~ '^[0-9A-Za-z-]+$')),
  add constraint purchases_notes_ok check (public.texto_largo_ok(notes, 300)),
  add constraint purchases_void_reason_ok check (public.texto_ok(void_reason, 150)),
  add constraint purchases_total_ok check (public.monto_ok(total));

alter table public.purchase_items
  add constraint purchase_items_quantity_ok check (public.cantidad_ok(quantity)),
  add constraint purchase_items_amounts_ok check (
    public.monto_ok(unit_cost) and public.monto_ok(line_total) and public.monto_ok(new_sale_price));

-- ============ Presupuestos ============
alter table public.quotes
  add constraint quotes_client_name_ok check (public.texto_ok(client_name, 80)),
  add constraint quotes_notes_ok check (public.texto_largo_ok(notes, 300)),
  add constraint quotes_amounts_ok check (
    public.monto_ok(subtotal) and public.monto_ok(discount) and public.monto_ok(total) and discount <= subtotal);

alter table public.quote_items
  add constraint quote_items_description_ok check (public.texto_ok(description, 120)),
  add constraint quote_items_unit_ok check (public.texto_ok(unit, 20)),
  add constraint quote_items_quantity_ok check (public.cantidad_ok(quantity)),
  add constraint quote_items_amounts_ok check (public.monto_ok(unit_price) and public.monto_ok(line_total));

-- ============ Movimientos ============
alter table public.stock_movements
  add constraint stock_movements_reason_ok check (public.texto_ok(reason, 150));

-- ============ Datos del negocio ============
alter table public.business_settings
  add constraint business_name_ok check (public.texto_ok(name, 80, 2)),
  add constraint business_tagline_ok check (public.texto_ok(tagline, 60)),
  add constraint business_phone_ok check (phone ~ '^\+?[0-9 ()-]{6,20}$'),
  add constraint business_city_ok check (public.texto_ok(city, 60)),
  add constraint business_address_ok check (public.texto_ok(address, 150)),
  add constraint business_ruc_ok check (ruc is null or ruc ~ '^[0-9]{5,8}-[0-9]$'),
  add constraint business_email_ok check (email is null or (char_length(email) <= 100 and email ~ '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$')),
  add constraint business_logo_ok check (logo_url is null or (char_length(logo_url) <= 500 and logo_url ~ '^https://')),
  add constraint business_notes_ok check (public.texto_largo_ok(receipt_note, 300) and public.texto_largo_ok(quote_note, 300));

-- Los helpers los usan los CHECK: los ejecuta quien inserta (authenticated o las funciones).
revoke all on function public.texto_ok(text, int, int), public.texto_largo_ok(text, int),
  public.monto_ok(bigint), public.cantidad_ok(numeric) from public, anon;
grant execute on function public.texto_ok(text, int, int), public.texto_largo_ok(text, int),
  public.monto_ok(bigint), public.cantidad_ok(numeric) to authenticated;
