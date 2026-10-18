-- Keep historical order snapshots when a menu item is permanently removed.
-- order_items stores product/name/price snapshots independently of this FK.
alter table public.order_items
  drop constraint if exists order_items_menu_item_id_fkey;

alter table public.order_items
  add constraint order_items_menu_item_id_fkey
  foreign key (menu_item_id)
  references public.menu_items(id)
  on delete set null;

notify pgrst, 'reload schema';
