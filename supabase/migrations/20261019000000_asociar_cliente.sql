-- "Asociar cliente" desde Movimientos: vincula un cliente a una venta ya hecha
-- (guarda una copia de sus datos, como al vender). Solo ventas activas.
create or replace function public.set_sale_client(p_sale_id uuid, p_client_id uuid)
returns public.sales
language plpgsql security definer set search_path = '' as $$
declare
  v_sale public.sales%rowtype;
  v_client public.clients%rowtype;
begin
  perform public.assert_can_write();
  select * into v_sale from public.sales where id = p_sale_id for update;
  if not found then raise exception 'La venta no existe.' using errcode = 'P0001'; end if;
  if v_sale.status <> 'activa' then
    raise exception 'La venta está anulada; no se le puede cambiar el cliente.' using errcode = 'P0001';
  end if;
  if p_client_id is not null then
    select * into v_client from public.clients where id = p_client_id;
    if not found then raise exception 'El cliente no existe.' using errcode = 'P0001'; end if;
  end if;
  update public.sales set
    client_id = v_client.id, client_name = v_client.full_name, client_phone = v_client.phone,
    client_document = v_client.document, client_address = v_client.address
  where id = p_sale_id
  returning * into v_sale;
  return v_sale;
end;
$$;
revoke all on function public.set_sale_client(uuid, uuid) from public, anon;
grant execute on function public.set_sale_client(uuid, uuid) to authenticated;
