-- Cup subtypes (cup_hot/cup_iced) and user-defined inventory types are stored
-- in inventory_type, so the legacy enum-like check must be removed.
alter table public.inventory_items
  drop constraint if exists inventory_items_inventory_type_check;

notify pgrst, 'reload schema';
