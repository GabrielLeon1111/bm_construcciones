-- Revisión de seguridad (19/10/2026)

-- 1) La vista de líneas de venta respeta las reglas (RLS) de quien consulta:
--    solo los miembros del negocio ven las ventas.
alter view public.v_sale_lines set (security_invoker = true);

-- 2) La versión vieja de create_purchase (sin día de compra) ya no se usa.
revoke execute on function public.create_purchase(jsonb, text, text, text, uuid) from authenticated, public, anon;

-- 3) No se puede crear dos veces el mismo producto (mismo nombre y marca),
--    por ejemplo desde dos celulares a la vez.
create unique index if not exists products_name_unique
  on public.products (lower(btrim(name)), lower(coalesce(btrim(brand), '')));
