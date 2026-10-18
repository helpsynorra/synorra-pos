-- Restore the atomic order deletion RPC if its original migration was skipped.
-- Stock is returned from persisted usage logs before dependent rows cascade.
create or replace function public.delete_order_atomic(p_order_id text)
returns jsonb
language plpgsql
as $$
declare
  v_order_id text;
  v_voided boolean;
  v_usage record;
begin
  select id, voided
    into v_order_id, v_voided
    from public.orders
   where id = p_order_id
   for update;

  if v_order_id is null then
    return jsonb_build_object('ok', false, 'error', 'ORDER_NOT_FOUND');
  end if;

  -- Voided orders already had their stock restored when they were voided.
  if not v_voided then
    for v_usage in
      select inventory_item_id, used_amount
        from public.usage_logs
       where order_id = p_order_id
         and inventory_item_id is not null
    loop
      update public.inventory_items
         set stock = stock + v_usage.used_amount
       where id = v_usage.inventory_item_id;
    end loop;
  end if;

  -- Existing FK cascades remove order_items, usage_logs, and print jobs.
  delete from public.orders where id = p_order_id;

  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function public.delete_order_atomic(text) from public, anon, authenticated;
grant execute on function public.delete_order_atomic(text) to service_role;

notify pgrst, 'reload schema';
