-- Keep a cup's menu size separate from its editable inventory item name.
alter table public.inventory_items
  add column if not exists cup_size text null;

notify pgrst, 'reload schema';
