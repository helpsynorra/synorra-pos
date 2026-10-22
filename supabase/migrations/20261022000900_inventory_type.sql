-- Distinguish cup stock from recipe ingredients in the admin inventory form.
-- Existing inventory rows remain nullable and keep their current behavior.
alter table public.inventory_items
  add column if not exists inventory_type text null;
