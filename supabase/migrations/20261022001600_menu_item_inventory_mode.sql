-- Let menu products either deduct a stock item directly or use their recipe.
alter table public.menu_items
  add column if not exists inventory_mode text not null default 'stock_and_recipe'
  check (inventory_mode in ('stock_only', 'stock_and_recipe'));

alter table public.menu_items
  add column if not exists stock_inventory_item_id text null,
  add column if not exists stock_usage_amount numeric null;

notify pgrst, 'reload schema';
