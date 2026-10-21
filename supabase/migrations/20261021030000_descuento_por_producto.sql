-- =================================================================
--  DESCUENTO POR PRODUCTO (ventas y presupuestos)
--  - Cada línea puede tener un descuento en % o en monto. Se guarda el monto
--    en guaraníes (line_discount) y, si fue en %, el porcentaje (discount_pct).
--  - line_total queda YA descontado: los reportes de ganancia y las devoluciones
--    lo toman solos. El descuento al total de la venta sigue aparte.
-- =================================================================
alter table public.sale_items
  add column if not exists line_discount integer not null default 0 check (line_discount >= 0),
  add column if not exists discount_pct numeric(5,2) check (discount_pct is null or (discount_pct > 0 and discount_pct <= 100));
alter table public.quote_items
  add column if not exists line_discount integer not null default 0 check (line_discount >= 0),
  add column if not exists discount_pct numeric(5,2) check (discount_pct is null or (discount_pct > 0 and discount_pct <= 100));
grant select (line_discount, discount_pct) on public.sale_items to authenticated;

-- create_sale y save_quote (aplicado en el servidor el 21/10/2026): leen 'discount' y
-- 'discount_pct' de cada ítem, validan 0 <= descuento <= total de la línea y 1..100 %,
-- restan el descuento de line_total y lo guardan en line_discount / discount_pct.
