-- Allow inventory items that are neither cups nor recipe ingredients,
-- such as plates and other reusable supplies.
alter table public.inventory_items
  drop constraint if exists inventory_items_inventory_type_check;
