-- Custom inventory types (for example, Plate) are stored as user-entered text.
alter table public.inventory_items
  drop constraint if exists inventory_items_inventory_type_check;
