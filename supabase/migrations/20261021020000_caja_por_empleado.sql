-- =================================================================
--  UNA CAJA POR EMPLEADO (como en el supermercado)
--  - Cada empleado abre su caja; puede haber varias abiertas a la vez,
--    pero una sola por persona.
--  - Las ventas de cada uno van a su caja (totales por quien abrió).
--  - Solo se cobra con la caja PROPIA abierta.
--  - Cerrar o retirar: el dueño de la caja o el administrador.
-- =================================================================

-- Una abierta por persona (reemplaza a "una sola abierta en todo el negocio").
create unique index if not exists cash_sessions_una_abierta_por_usuario on public.cash_sessions (opened_by) where status = 'abierta';
drop index if exists public.cash_sessions_una_abierta;

-- Totales: solo las ventas de quien abrió la caja.
create or replace function public.totales_caja(p_desde timestamptz, p_hasta timestamptz, p_usuario uuid)
returns table (ventas integer, efectivo integer, transferencia integer)
language sql stable security definer set search_path to '' as $$
  select count(*)::int,
         coalesce(sum(case when total > 0 then round(paid_cash::numeric * (total - returned_amount) / total) else 0 end), 0)::int,
         coalesce(sum(case when total > 0 then round(paid_transfer::numeric * (total - returned_amount) / total) else 0 end), 0)::int
  from public.sales
  where status = 'activa' and created_by = p_usuario and created_at >= p_desde and created_at <= p_hasta;
$$;
revoke all on function public.totales_caja(timestamptz, timestamptz, uuid) from public, anon, authenticated;

-- (Aplicado en el servidor el 21/10/2026: abrir_caja y resumen_caja por usuario,
--  caja_con_totales, caja() con totales; cerrar_caja y retirar_caja con totales por
--  usuario y control de dueño/administrador; create_sale exige la caja propia abierta.)
