-- Inventory tracking is opt-in for each menu item. With neither mode selected,
-- sales do not deduct stock or recipe ingredients for that menu item.
alter table public.menu_items
  alter column inventory_mode set default 'none';

alter table public.menu_items
  drop constraint if exists menu_items_inventory_mode_check;

alter table public.menu_items
  add constraint menu_items_inventory_mode_check
  check (inventory_mode in ('none', 'stock_only', 'stock_and_recipe'));

-- Earlier versions assigned a tracking mode by default. Clear those implicit
-- selections so owners can opt in explicitly for each menu item.
update public.menu_items
set inventory_mode = 'none'
where inventory_mode in ('stock_only', 'stock_and_recipe');

notify pgrst, 'reload schema';
