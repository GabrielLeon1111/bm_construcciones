-- =====================================================================
--  BM. Construcciones – esquema inicial
--  Ventas, compras, stock con costo promedio ponderado, presupuestos,
--  clientes y datos del negocio.
--
--  Reglas generales:
--   * Montos en guaraníes como enteros. Cantidades con hasta 3 decimales
--     (1/2 camión, 2,5 metros, 0,75 kg).
--   * Solo los usuarios cargados en app_members pueden ver o tocar datos
--     (aunque alguien se registre con la clave pública, no ve nada).
--   * El stock y los totales solo cambian a través de las funciones de
--     abajo (security definer), así quedan siempre cuadrados con el
--     historial de movimientos.
--   * La licencia (prueba gratis / pago) se controla en app_license y se
--     verifica en el servidor antes de registrar cualquier movimiento.
-- =====================================================================

create extension if not exists pg_trgm with schema extensions;

-- ============ MIEMBROS Y LICENCIA ============
create table public.app_members (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create or replace function public.is_member()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.app_members where user_id = (select auth.uid()));
$$;

create table public.app_license (
  id int primary key default 1 check (id = 1),
  -- Último día de la prueba gratis. null = sin límite todavía.
  trial_until date,
  paid boolean not null default false,
  updated_at timestamptz not null default now()
);
insert into public.app_license (id) values (1);

create or replace function public.license_ok()
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(
    (select paid or trial_until is null
            or (now() at time zone 'America/Asuncion')::date <= trial_until
       from public.app_license where id = 1),
    true);
$$;

-- Corta cualquier operación si el usuario no es miembro o la licencia venció.
create or replace function public.assert_can_write()
returns void language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_member() then
    raise exception 'No tenés permiso para hacer esta operación.' using errcode = '42501';
  end if;
  if not public.license_ok() then
    raise exception 'El período de prueba terminó. Comunicate con soporte para seguir usando la app.'
      using errcode = 'P0001';
  end if;
end;
$$;

-- ============ DATOS DEL NEGOCIO ============
create table public.business_settings (
  id int primary key default 1 check (id = 1),
  name text not null default 'BM. Construcciones',
  tagline text not null default 'Venta de materiales',
  phone text not null default '0981000000',
  city text not null default 'Carapeguá',
  address text,
  ruc text,
  email text,
  logo_url text,
  receipt_note text,
  quote_note text default 'Precios sujetos a cambio sin previo aviso.',
  quote_validity_days int not null default 7 check (quote_validity_days between 1 and 90),
  updated_at timestamptz not null default now()
);
insert into public.business_settings (id) values (1);

-- ============ PRODUCTOS ============
create table public.products (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) > 0),
  category text not null default 'General',
  brand text,
  unit text not null default 'unidad',
  stock numeric(14,3) not null default 0 check (stock >= 0),
  avg_cost int not null default 0 check (avg_cost >= 0),
  sale_price int not null default 0 check (sale_price >= 0),
  min_stock numeric(14,3) not null default 0 check (min_stock >= 0),
  active boolean not null default true,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index products_name_trgm_idx on public.products using gin (name extensions.gin_trgm_ops);
create index products_category_idx on public.products (category);

-- ============ CLIENTES ============
create table public.clients (
  id uuid primary key default gen_random_uuid(),
  full_name text not null check (length(trim(full_name)) > 0),
  phone text,
  document text,
  address text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index clients_name_trgm_idx on public.clients using gin (full_name extensions.gin_trgm_ops);

-- ============ COMPRAS ============
create table public.purchases (
  id uuid primary key default gen_random_uuid(),
  number bigint generated always as identity unique,
  supplier text,
  invoice_number text,
  notes text,
  total int not null default 0,
  status text not null default 'activa' check (status in ('activa', 'anulada')),
  void_reason text,
  voided_at timestamptz,
  idempotency_key uuid unique,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now()
);
create index purchases_created_at_idx on public.purchases (created_at);

create table public.purchase_items (
  id uuid primary key default gen_random_uuid(),
  purchase_id uuid not null references public.purchases(id) on delete cascade,
  position int not null,
  product_id uuid not null references public.products(id) on delete restrict,
  product_name text not null,
  unit text not null,
  quantity numeric(14,3) not null check (quantity > 0),
  unit_cost int not null check (unit_cost >= 0),
  line_total int not null,
  new_sale_price int
);
create index purchase_items_purchase_idx on public.purchase_items (purchase_id);
create index purchase_items_product_idx on public.purchase_items (product_id);

-- ============ PRESUPUESTOS ============
create table public.quotes (
  id uuid primary key default gen_random_uuid(),
  number bigint generated always as identity unique,
  client_id uuid references public.clients(id) on delete set null,
  client_name text,
  status text not null default 'pendiente' check (status in ('pendiente', 'vendido', 'anulado')),
  subtotal int not null default 0,
  discount int not null default 0,
  total int not null default 0,
  notes text,
  valid_until date,
  sale_id uuid,
  idempotency_key uuid unique,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index quotes_client_idx on public.quotes (client_id);
create index quotes_created_at_idx on public.quotes (created_at);

create table public.quote_items (
  id uuid primary key default gen_random_uuid(),
  quote_id uuid not null references public.quotes(id) on delete cascade,
  position int not null,
  product_id uuid references public.products(id) on delete set null,
  description text not null,
  unit text not null default 'unidad',
  quantity numeric(14,3) not null check (quantity > 0),
  unit_price int not null default 0 check (unit_price >= 0),
  is_gift boolean not null default false,
  line_total int not null
);
create index quote_items_quote_idx on public.quote_items (quote_id);

-- ============ VENTAS ============
create table public.sales (
  id uuid primary key default gen_random_uuid(),
  number bigint generated always as identity unique,
  client_id uuid references public.clients(id) on delete set null,
  -- Copia de los datos del cliente al momento de vender (para reimprimir igual).
  client_name text,
  client_phone text,
  client_document text,
  client_address text,
  payment_method text not null check (payment_method in ('efectivo', 'transferencia', 'qr')),
  subtotal int not null default 0,
  discount int not null default 0,
  total int not null default 0,
  cost_total int not null default 0,
  notes text,
  quote_id uuid references public.quotes(id) on delete set null,
  status text not null default 'activa' check (status in ('activa', 'anulada')),
  void_reason text,
  voided_at timestamptz,
  idempotency_key uuid unique,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now()
);
create index sales_created_at_idx on public.sales (created_at);
create index sales_client_idx on public.sales (client_id);
create index sales_quote_idx on public.sales (quote_id);

alter table public.quotes
  add constraint quotes_sale_fk foreign key (sale_id) references public.sales(id) on delete set null;
create index quotes_sale_idx on public.quotes (sale_id);

create table public.sale_items (
  id uuid primary key default gen_random_uuid(),
  sale_id uuid not null references public.sales(id) on delete cascade,
  position int not null,
  product_id uuid references public.products(id) on delete set null,
  description text not null,
  unit text not null default 'unidad',
  quantity numeric(14,3) not null check (quantity > 0),
  unit_price int not null default 0 check (unit_price >= 0),
  unit_cost int not null default 0,
  is_gift boolean not null default false,
  line_total int not null
);
create index sale_items_sale_idx on public.sale_items (sale_id);
create index sale_items_product_idx on public.sale_items (product_id);

-- ============ MOVIMIENTOS DE STOCK ============
create table public.stock_movements (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete restrict,
  movement_type text not null check (movement_type in
    ('compra', 'venta', 'ajuste', 'anulacion_venta', 'anulacion_compra')),
  quantity numeric(14,3) not null,
  stock_before numeric(14,3) not null,
  stock_after numeric(14,3) not null,
  unit_cost int,
  avg_cost_before int not null,
  avg_cost_after int not null,
  unit_price int,
  sale_id uuid references public.sales(id) on delete set null,
  purchase_id uuid references public.purchases(id) on delete set null,
  reason text,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now()
);
create index stock_movements_product_idx on public.stock_movements (product_id);
create index stock_movements_created_at_idx on public.stock_movements (created_at);
create index stock_movements_sale_idx on public.stock_movements (sale_id);
create index stock_movements_purchase_idx on public.stock_movements (purchase_id);

-- ============ updated_at ============
create or replace function public.set_updated_at()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger products_updated_at before update on public.products
  for each row execute function public.set_updated_at();
create trigger clients_updated_at before update on public.clients
  for each row execute function public.set_updated_at();
create trigger quotes_updated_at before update on public.quotes
  for each row execute function public.set_updated_at();
create trigger business_settings_updated_at before update on public.business_settings
  for each row execute function public.set_updated_at();

-- =====================================================================
--  FUNCIONES DE NEGOCIO
-- =====================================================================

-- Normaliza la lista de ítems que manda la app:
-- [{product_id?, description?, unit?, quantity, unit_price, is_gift?}]
-- (para compras: [{product_id, quantity, unit_cost, new_sale_price?}])

-- ---------- VENTA ----------
create or replace function public.create_sale(
  p_items jsonb,
  p_payment_method text,
  p_client_id uuid default null,
  p_discount int default 0,
  p_notes text default null,
  p_quote_id uuid default null,
  p_idempotency_key uuid default null
) returns public.sales
language plpgsql security definer set search_path = '' as $$
declare
  v_sale public.sales%rowtype;
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
begin
  perform public.assert_can_write();

  if p_idempotency_key is not null then
    select * into v_sale from public.sales where idempotency_key = p_idempotency_key;
    if found then return v_sale; end if;
  end if;

  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'Agregá al menos un producto a la venta.' using errcode = 'P0001';
  end if;
  if p_payment_method not in ('efectivo', 'transferencia', 'qr') then
    raise exception 'Elegí el método de pago.' using errcode = 'P0001';
  end if;
  if coalesce(p_discount, 0) < 0 then
    raise exception 'El descuento no puede ser negativo.' using errcode = 'P0001';
  end if;

  if p_client_id is not null then
    select * into v_client from public.clients where id = p_client_id;
  end if;

  insert into public.sales (
    client_id, client_name, client_phone, client_document, client_address,
    payment_method, notes, quote_id, idempotency_key
  ) values (
    v_client.id, v_client.full_name, v_client.phone, v_client.document, v_client.address,
    p_payment_method, nullif(trim(p_notes), ''), p_quote_id, p_idempotency_key
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
    update public.quotes set status = 'vendido', sale_id = v_sale.id
      where id = p_quote_id and status = 'pendiente';
  end if;

  return v_sale;
end;
$$;

-- ---------- ANULAR VENTA ----------
-- Devuelve el stock al costo con que salió y deja el registro marcado como anulado.
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

-- ---------- COMPRA ----------
-- Suma stock y recalcula el costo promedio ponderado.
-- Ej: 10 bolsas a 50.000 + 10 a 60.000 => 55.000 por bolsa.
create or replace function public.create_purchase(
  p_items jsonb,
  p_supplier text default null,
  p_invoice_number text default null,
  p_notes text default null,
  p_idempotency_key uuid default null
) returns public.purchases
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
begin
  perform public.assert_can_write();

  if p_idempotency_key is not null then
    select * into v_purchase from public.purchases where idempotency_key = p_idempotency_key;
    if found then return v_purchase; end if;
  end if;

  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'Agregá al menos un producto a la compra.' using errcode = 'P0001';
  end if;

  insert into public.purchases (supplier, invoice_number, notes, idempotency_key)
  values (nullif(trim(p_supplier), ''), nullif(trim(p_invoice_number), ''), nullif(trim(p_notes), ''), p_idempotency_key)
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

-- ---------- ANULAR COMPRA ----------
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

-- ---------- AJUSTE DE STOCK ----------
-- Fija el stock a un valor (recuento, rotura, stock inicial). Si sube y se
-- indica costo, ese ingreso entra al costo promedio.
create or replace function public.adjust_stock(
  p_product_id uuid,
  p_new_stock numeric,
  p_reason text,
  p_unit_cost int default null
) returns public.stock_movements
language plpgsql security definer set search_path = '' as $$
declare
  v_product public.products%rowtype;
  v_diff numeric(14,3);
  v_new_avg int;
  v_movement public.stock_movements%rowtype;
begin
  perform public.assert_can_write();
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

  update public.products set stock = p_new_stock, avg_cost = v_new_avg where id = v_product.id;

  insert into public.stock_movements (
    product_id, movement_type, quantity, stock_before, stock_after,
    unit_cost, avg_cost_before, avg_cost_after, reason
  ) values (
    v_product.id, 'ajuste', v_diff, v_product.stock, p_new_stock,
    coalesce(p_unit_cost, v_product.avg_cost), v_product.avg_cost, v_new_avg, trim(p_reason)
  ) returning * into v_movement;

  return v_movement;
end;
$$;

-- ---------- PRESUPUESTO (crear o editar) ----------
create or replace function public.save_quote(
  p_items jsonb,
  p_quote_id uuid default null,
  p_client_id uuid default null,
  p_discount int default 0,
  p_notes text default null,
  p_valid_until date default null,
  p_idempotency_key uuid default null
) returns public.quotes
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
begin
  perform public.assert_can_write();

  if p_quote_id is null and p_idempotency_key is not null then
    select * into v_quote from public.quotes where idempotency_key = p_idempotency_key;
    if found then return v_quote; end if;
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
    insert into public.quotes (client_id, client_name, notes, valid_until, idempotency_key)
    values (p_client_id, v_client_name, nullif(trim(p_notes), ''), p_valid_until, p_idempotency_key)
    returning * into v_quote;
  else
    select * into v_quote from public.quotes where id = p_quote_id for update;
    if not found then raise exception 'El presupuesto no existe.' using errcode = 'P0001'; end if;
    if v_quote.status <> 'pendiente' then
      raise exception 'Este presupuesto ya fue vendido o anulado; no se puede editar.' using errcode = 'P0001';
    end if;
    update public.quotes set client_id = p_client_id, client_name = v_client_name,
      notes = nullif(trim(p_notes), ''), valid_until = p_valid_until
      where id = p_quote_id;
    delete from public.quote_items where quote_id = p_quote_id;
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
      quote_id, position, product_id, description, unit, quantity, unit_price, is_gift, line_total
    ) values (
      v_quote.id, v_pos, v_product.id, v_desc, v_unit, v_qty, v_price, v_gift, v_line
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

create or replace function public.cancel_quote(p_quote_id uuid)
returns public.quotes
language plpgsql security definer set search_path = '' as $$
declare
  v_quote public.quotes%rowtype;
begin
  perform public.assert_can_write();
  update public.quotes set status = 'anulado'
    where id = p_quote_id and status = 'pendiente' returning * into v_quote;
  if not found then
    raise exception 'Solo se pueden anular presupuestos pendientes.' using errcode = 'P0001';
  end if;
  return v_quote;
end;
$$;

-- =====================================================================
--  VISTAS Y REPORTES
-- =====================================================================

-- Una fila por línea vendida (ventas activas). El descuento de la venta se
-- reparte proporcionalmente entre sus líneas para que la ganancia por
-- producto sume igual que la ganancia total.
create view public.v_sale_lines with (security_invoker = true) as
select
  si.id,
  s.id as sale_id,
  s.number as sale_number,
  s.created_at,
  s.payment_method,
  s.client_id,
  si.product_id,
  si.description,
  coalesce(p.category, 'Sin categoría') as category,
  si.unit,
  si.quantity,
  si.unit_price,
  si.unit_cost,
  si.is_gift,
  si.line_total,
  case when s.subtotal > 0
    then round(si.line_total::numeric * s.total / s.subtotal)::int
    else 0 end as net_revenue,
  round(si.quantity * si.unit_cost)::int as cost
from public.sale_items si
join public.sales s on s.id = si.sale_id
left join public.products p on p.id = si.product_id
where s.status = 'activa';

-- Panel de inicio en una sola llamada.
create or replace function public.dashboard_summary()
returns jsonb
language plpgsql stable security invoker set search_path = '' as $$
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
      and created_at >= ((v_today - interval '12 months')::date)::timestamp at time zone 'America/Asuncion'
  ),
  periods as (
    select
      jsonb_build_object(
        'today',      jsonb_build_object('sales', coalesce(sum(total) filter (where d = v_today), 0),
                                         'profit', coalesce(sum(total - cost_total) filter (where d = v_today), 0),
                                         'count', count(*) filter (where d = v_today)),
        'week',       jsonb_build_object('sales', coalesce(sum(total) filter (where d >= v_week), 0),
                                         'profit', coalesce(sum(total - cost_total) filter (where d >= v_week), 0),
                                         'count', count(*) filter (where d >= v_week)),
        'month',      jsonb_build_object('sales', coalesce(sum(total) filter (where d >= v_month), 0),
                                         'profit', coalesce(sum(total - cost_total) filter (where d >= v_month), 0),
                                         'count', count(*) filter (where d >= v_month)),
        'prev_month', jsonb_build_object('sales', coalesce(sum(total) filter (where d >= v_prev_month and d < v_month), 0),
                                         'profit', coalesce(sum(total - cost_total) filter (where d >= v_prev_month and d < v_month), 0),
                                         'count', count(*) filter (where d >= v_prev_month and d < v_month)),
        'payments',   jsonb_build_object(
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
      'capital', coalesce(sum(round(stock * avg_cost)) filter (where active), 0),
      'low_stock', count(*) filter (where active and stock > 0 and stock <= min_stock),
      'out_of_stock', count(*) filter (where active and stock = 0),
      'products', count(*) filter (where active)
    ) as j
    from public.products
  ),
  low_list as (
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', id, 'name', name, 'unit', unit, 'stock', stock, 'min_stock', min_stock) order by stock / nullif(min_stock, 0) nulls first, name), '[]'::jsonb) as j
    from (
      select * from public.products
      where active and stock <= min_stock
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

-- Arqueo / reporte para un rango de fechas (inclusive), en hora de Paraguay.
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

-- =====================================================================
--  PERMISOS Y RLS
-- =====================================================================
alter table public.app_members enable row level security;
alter table public.app_license enable row level security;
alter table public.business_settings enable row level security;
alter table public.products enable row level security;
alter table public.clients enable row level security;
alter table public.purchases enable row level security;
alter table public.purchase_items enable row level security;
alter table public.quotes enable row level security;
alter table public.quote_items enable row level security;
alter table public.sales enable row level security;
alter table public.sale_items enable row level security;
alter table public.stock_movements enable row level security;

-- Nadie anónimo toca nada.
revoke all on all tables in schema public from anon;
revoke all on all functions in schema public from anon, public;

-- Lo que se escribe solo por funciones queda en solo-lectura para la app.
revoke all on public.app_members, public.app_license, public.purchases, public.purchase_items,
  public.quotes, public.quote_items, public.sales, public.sale_items, public.stock_movements
  from authenticated;
grant select on public.app_members, public.app_license, public.purchases, public.purchase_items,
  public.quotes, public.quote_items, public.sales, public.sale_items, public.stock_movements
  to authenticated;

-- Productos: la app edita los datos, pero no el stock ni el costo (eso es por funciones).
revoke all on public.products from authenticated;
grant select, delete on public.products to authenticated;
grant insert (name, category, brand, unit, sale_price, min_stock, active, notes),
      update (name, category, brand, unit, sale_price, min_stock, active, notes)
  on public.products to authenticated;

revoke all on public.business_settings from authenticated;
grant select on public.business_settings to authenticated;
grant update (name, tagline, phone, city, address, ruc, email, logo_url, receipt_note, quote_note, quote_validity_days)
  on public.business_settings to authenticated;

revoke all on public.clients from authenticated;
grant select, insert, update, delete on public.clients to authenticated;

grant select on public.v_sale_lines to authenticated;

create policy members_own_row on public.app_members for select to authenticated
  using (user_id = (select auth.uid()));
create policy members_read on public.app_license for select to authenticated
  using ((select public.is_member()));

create policy members_read on public.business_settings for select to authenticated
  using ((select public.is_member()));
create policy members_update on public.business_settings for update to authenticated
  using ((select public.is_member())) with check ((select public.is_member()));

create policy members_all on public.products for all to authenticated
  using ((select public.is_member())) with check ((select public.is_member()));
create policy members_all on public.clients for all to authenticated
  using ((select public.is_member())) with check ((select public.is_member()));

create policy members_read on public.purchases for select to authenticated using ((select public.is_member()));
create policy members_read on public.purchase_items for select to authenticated using ((select public.is_member()));
create policy members_read on public.quotes for select to authenticated using ((select public.is_member()));
create policy members_read on public.quote_items for select to authenticated using ((select public.is_member()));
create policy members_read on public.sales for select to authenticated using ((select public.is_member()));
create policy members_read on public.sale_items for select to authenticated using ((select public.is_member()));
create policy members_read on public.stock_movements for select to authenticated using ((select public.is_member()));

grant execute on function
  public.is_member(), public.license_ok(),
  public.create_sale(jsonb, text, uuid, int, text, uuid, uuid),
  public.void_sale(uuid, text),
  public.create_purchase(jsonb, text, text, text, uuid),
  public.void_purchase(uuid, text),
  public.adjust_stock(uuid, numeric, text, int),
  public.save_quote(jsonb, uuid, uuid, int, text, date, uuid),
  public.cancel_quote(uuid),
  public.dashboard_summary(),
  public.sales_report(date, date)
  to authenticated;

-- Las tablas que se creen después no quedan abiertas a anon por defecto.
alter default privileges in schema public revoke all on tables from anon;
alter default privileges in schema public revoke all on functions from anon, public;

-- ============ Storage: logo del negocio ============
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('business', 'business', true, 2097152, array['image/png', 'image/jpeg', 'image/webp'])
on conflict (id) do nothing;

create policy "members_upload_business" on storage.objects for insert to authenticated
  with check (bucket_id = 'business' and (select public.is_member()));
create policy "members_update_business" on storage.objects for update to authenticated
  using (bucket_id = 'business' and (select public.is_member()));
create policy "members_delete_business" on storage.objects for delete to authenticated
  using (bucket_id = 'business' and (select public.is_member()));
