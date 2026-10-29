  -- Never remove an order's usage ledger unless every linked stock adjustment
-- was restored successfully. Treat legacy NULL voided flags as active orders.
create or replace function public.delete_order_atomic(p_order_id text)
returns jsonb
language plpgsql
as $$
declare
  v_order_id text;
  v_voided boolean;
  v_usage record;
  v_updated_rows integer;
begin
  select id, voided
    into v_order_id, v_voided
    from public.orders
   where id = p_order_id
   for update;

  if v_order_id is null then
    return jsonb_build_object('ok', false, 'error', 'ORDER_NOT_FOUND');
  end if;

  if not coalesce(v_voided, false) then
    for v_usage in
      select inventory_item_id, used_amount
        from public.usage_logs
       where order_id = p_order_id
         and inventory_item_id is not null
    loop
      update public.inventory_items
         set stock = stock + v_usage.used_amount
       where id = v_usage.inventory_item_id;

      get diagnostics v_updated_rows = row_count;
      if v_updated_rows = 0 then
        raise exception 'ORDER_DELETE_STOCK_RESTORE_FAILED:%', v_usage.inventory_item_id;
      end if;
    end loop;
  end if;

  delete from public.usage_logs where order_id = p_order_id;
  delete from public.order_items where order_id = p_order_id;
  delete from public.orders where id = p_order_id;

  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function public.delete_order_atomic(text) from public, anon, authenticated;
grant execute on function public.delete_order_atomic(text) to service_role;

notify pgrst, 'reload schema';
