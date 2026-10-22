-- Allow a recipe to deduct additional cup stock items on each sale.
alter table public.recipe_costings
  add column if not exists extra_cup_inventory_item_ids text[] not null default '{}';

create or replace function public.save_recipe_costing_for_owner(
  p_owner_id text,
  p_id text,
  p_name text,
  p_hot_cup_inventory_item_id text,
  p_iced_cup_inventory_item_id text,
  p_other_cup_inventory_item_id text,
  p_extra_cup_inventory_item_ids text[],
  p_menu_items jsonb,
  p_ingredients jsonb
)
returns void
language plpgsql
as $$
begin
  perform set_config('synorra.owner_id', p_owner_id, true);
  perform public.save_recipe_costing_for_owner(
    p_owner_id,
    p_id,
    p_name,
    p_hot_cup_inventory_item_id,
    p_iced_cup_inventory_item_id,
    p_other_cup_inventory_item_id,
    p_menu_items,
    p_ingredients
  );
  update public.recipe_costings
  set extra_cup_inventory_item_ids = coalesce(p_extra_cup_inventory_item_ids, '{}'),
      updated_at = now()
  where id = p_id;
end;
$$;

revoke all on function public.save_recipe_costing_for_owner(text, text, text, text, text, text, text[], jsonb, jsonb)
  from public, anon, authenticated;
grant execute on function public.save_recipe_costing_for_owner(text, text, text, text, text, text, text[], jsonb, jsonb)
  to service_role;

notify pgrst, 'reload schema';
