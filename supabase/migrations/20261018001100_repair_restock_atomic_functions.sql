-- Repair deployments where the restock RPC/snapshot migration was skipped.
-- The signatures match the arguments sent by src/lib/store.ts.
alter table public.restocks
  add column if not exists purchase_qty numeric,
  add column if not exists purchase_unit text;

-- Remove the older signatures so PostgREST has one canonical overload.
drop function if exists public.create_restock_atomic(text, text, text, numeric, timestamptz);
drop function if exists public.edit_restock_atomic(text, text, numeric, text, text, numeric, timestamptz);

create or replace function public.create_restock_atomic(
  p_id text,
  p_inventory_item_id text,
  p_item_name_snapshot text,
  p_quantity_added numeric,
  p_created_at timestamptz,
  p_purchase_qty numeric default null,
  p_purchase_unit text default null
)
returns jsonb
language plpgsql
as $$
begin
  if p_id is null or length(trim(p_id)) = 0 then
    raise exception 'create_restock_atomic: p_id is required';
  end if;
  if p_item_name_snapshot is null or length(trim(p_item_name_snapshot)) = 0 then
    raise exception 'create_restock_atomic: item name is required';
  end if;
  if p_quantity_added is null or p_quantity_added <= 0 then
    raise exception 'create_restock_atomic: quantity must be greater than zero';
  end if;

  insert into public.restocks (
    id, inventory_item_id, item_name_snapshot, quantity_added,
    purchase_qty, purchase_unit, created_at
  ) values (
    p_id, p_inventory_item_id, trim(p_item_name_snapshot), p_quantity_added,
    p_purchase_qty, nullif(trim(p_purchase_unit), ''), p_created_at
  );

  if p_inventory_item_id is not null then
    update public.inventory_items
       set stock = stock + p_quantity_added
     where id = p_inventory_item_id;
    if not found then
      raise exception 'create_restock_atomic: inventory item % not found', p_inventory_item_id;
    end if;
  end if;

  return jsonb_build_object('ok', true);
end;
$$;

create or replace function public.edit_restock_atomic(
  p_id text,
  p_old_inventory_item_id text,
  p_old_quantity numeric,
  p_new_inventory_item_id text,
  p_new_item_name_snapshot text,
  p_new_quantity numeric,
  p_new_created_at timestamptz,
  p_new_purchase_qty numeric default null,
  p_new_purchase_unit text default null
)
returns jsonb
language plpgsql
as $$
declare
  v_restock public.restocks%rowtype;
begin
  select * into v_restock
    from public.restocks
   where id = p_id
   for update;
  if not found then
    raise exception 'edit_restock_atomic: restock % not found', p_id;
  end if;
  if p_new_item_name_snapshot is null or length(trim(p_new_item_name_snapshot)) = 0 then
    raise exception 'edit_restock_atomic: item name is required';
  end if;
  if p_new_quantity is null or p_new_quantity <= 0 then
    raise exception 'edit_restock_atomic: quantity must be greater than zero';
  end if;

  -- Use the stored old values so stale clients cannot corrupt stock totals.
  if v_restock.inventory_item_id is not null then
    update public.inventory_items
       set stock = greatest(0, stock - v_restock.quantity_added)
     where id = v_restock.inventory_item_id;
  end if;
  if p_new_inventory_item_id is not null then
    update public.inventory_items
       set stock = stock + p_new_quantity
     where id = p_new_inventory_item_id;
    if not found then
      raise exception 'edit_restock_atomic: inventory item % not found', p_new_inventory_item_id;
    end if;
  end if;

  update public.restocks
     set inventory_item_id = p_new_inventory_item_id,
         item_name_snapshot = trim(p_new_item_name_snapshot),
         quantity_added = p_new_quantity,
         purchase_qty = p_new_purchase_qty,
         purchase_unit = nullif(trim(p_new_purchase_unit), ''),
         created_at = p_new_created_at
   where id = p_id;

  return jsonb_build_object('ok', true);
end;
$$;

create or replace function public.delete_restock_atomic(
  p_id text,
  p_inventory_item_id text,
  p_quantity_added numeric
)
returns jsonb
language plpgsql
as $$
declare
  v_restock public.restocks%rowtype;
  v_item_id text;
  v_matches integer;
begin
  select * into v_restock
    from public.restocks
   where id = p_id
   for update;
  if not found then
    raise exception 'delete_restock_atomic: restock % not found', p_id;
  end if;

  v_item_id := v_restock.inventory_item_id;
  if v_item_id is null then
    select count(*) into v_matches
      from public.inventory_items
     where lower(trim(name)) = lower(trim(v_restock.item_name_snapshot));
    if v_matches = 1 then
      select id into v_item_id
        from public.inventory_items
       where lower(trim(name)) = lower(trim(v_restock.item_name_snapshot));
    elsif v_matches > 1 then
      raise exception 'delete_restock_atomic: ambiguous inventory item name for restock %', p_id;
    end if;
  end if;

  if v_item_id is not null then
    update public.inventory_items
       set stock = greatest(0, stock - v_restock.quantity_added)
     where id = v_item_id;
    if not found then
      v_item_id := null;
    end if;
  end if;

  delete from public.restocks where id = p_id;
  return jsonb_build_object(
    'ok', true,
    'reversed', v_item_id is not null,
    'inventoryItemId', v_item_id,
    'quantityAdded', v_restock.quantity_added
  );
end;
$$;

revoke all on function public.create_restock_atomic(text, text, text, numeric, timestamptz, numeric, text) from public, anon, authenticated;
revoke all on function public.edit_restock_atomic(text, text, numeric, text, text, numeric, timestamptz, numeric, text) from public, anon, authenticated;
revoke all on function public.delete_restock_atomic(text, text, numeric) from public, anon, authenticated;
grant execute on function public.create_restock_atomic(text, text, text, numeric, timestamptz, numeric, text) to service_role;
grant execute on function public.edit_restock_atomic(text, text, numeric, text, text, numeric, timestamptz, numeric, text) to service_role;
grant execute on function public.delete_restock_atomic(text, text, numeric) to service_role;

notify pgrst, 'reload schema';
