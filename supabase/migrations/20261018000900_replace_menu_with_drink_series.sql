-- Replace the old starter catalog with the supplied Coffee ZZ menu.
-- Order item snapshots preserve historical slips; their optional live
-- menu_item_id is set to NULL by its existing FK when an old item is removed.
begin;

create temporary table synorra_menu_categories (
  id text primary key,
  name text not null,
  type text not null
) on commit drop;

insert into synorra_menu_categories (id, name, type) values
  ('non-coffee', 'Non Coffee', 'drink'),
  ('soda-series', 'Soda Series', 'drink'),
  ('coffee-series', 'Coffee Series', 'drink'),
  ('milky-series', 'Milky Series', 'drink'),
  ('yogurt-series', 'Yogurt Series', 'drink'),
  ('milk-tea-series', 'Milk Tea Series', 'drink'),
  ('frappe-series', 'Frappe Series', 'drink');

insert into public.menu_categories (id, name, type)
select id, name, type from synorra_menu_categories
on conflict (id) do update set name = excluded.name, type = excluded.type;

create temporary table synorra_menu_items (
  id text primary key,
  name text not null,
  price integer not null,
  category_id text not null,
  image text not null,
  available boolean not null,
  types jsonb not null,
  styles jsonb not null,
  addons jsonb not null
) on commit drop;

with series(category, id_prefix, names, sizes) as (
  values
    ('Non Coffee', 'non-coffee', array['Iced Matcha', 'Iced Milo', 'Iced Choco', 'Choco Hazel Nut', 'Matcha Berry', 'Blueberry Matcha']::text[], '[{"name":"16oz","price":50},{"name":"22oz","price":70}]'::jsonb),
    ('Soda Series', 'soda', array['Green Apple', 'Strawberry', 'Blueberry', 'Mixed Berries', 'Lychee']::text[], '[{"name":"16oz","price":50},{"name":"22oz","price":70}]'::jsonb),
    ('Coffee Series', 'coffee', array['Caramel Macchiato', 'Spanish Latte', 'Vanilla Latte', 'Salted Caramel', 'Matcha Latte', 'Mocha Latte']::text[], '[{"name":"16oz","price":50},{"name":"22oz","price":70}]'::jsonb),
    ('Milky Series', 'milky', array['Strawberry Milk', 'Strawberry Matcha', 'Matcha Oreo', 'Cookies & Cream', 'Milo Lava', 'Choco Berry']::text[], '[{"name":"16oz","price":89},{"name":"22oz","price":109}]'::jsonb),
    ('Yogurt Series', 'yogurt', array['Strawberry', 'Blueberry', 'Green Apple', 'Mixed Berries']::text[], '[{"name":"16oz","price":50},{"name":"22oz","price":70}]'::jsonb),
    ('Milk Tea Series', 'milk-tea', array['Brown Sugar Boba', 'Okinawa', 'Wintermelon', 'Dark Choco', 'Cookies & Cream']::text[], '[{"name":"16oz","price":60},{"name":"22oz","price":80}]'::jsonb),
    ('Frappe Series', 'frappe', array['Strawberry Milk', 'Matcha', 'Matcha Oreo', 'Dark Choco Cookies', 'Java Chips']::text[], '[{"name":"22oz","price":129}]'::jsonb)
), expanded as (
  select
    id_prefix || '-' || trim(both '-' from regexp_replace(lower(item_name), '[^a-z0-9]+', '-', 'g')) as id,
    item_name as name,
    (sizes -> 0 ->> 'price')::integer as price,
    regexp_replace(lower(category), '[^a-z0-9]+', '-', 'g') as category_id,
    sizes
  from series
  cross join lateral unnest(names) as expanded_names(item_name)
)
insert into synorra_menu_items (id, name, price, category_id, image, available, types, styles, addons)
select
  expanded.id,
  expanded.name,
  expanded.price,
  expanded.category_id,
  '/images/logo.jpg',
  true,
  '[]'::jsonb,
  '["iced"]'::jsonb,
  (
    select jsonb_agg(jsonb_build_object(
      'id', 'size:' || regexp_replace(lower(size.value ->> 'name'), '[^a-z0-9]+', '-', 'g'),
      'name', size.value ->> 'name',
      'price', (size.value ->> 'price')::integer
    ))
    from jsonb_array_elements(expanded.sizes) as size(value)
  )
from expanded;

insert into public.menu_items (id, name, price, category_id, image, available, types, styles, addons)
select id, name, price, category_id, image, available, types, styles, addons
from synorra_menu_items
on conflict (id) do update set
  name = excluded.name,
  price = excluded.price,
  category_id = excluded.category_id,
  image = excluded.image,
  available = excluded.available,
  types = excluded.types,
  styles = excluded.styles,
  addons = excluded.addons;

delete from public.menu_items
where id not in (select id from synorra_menu_items);

delete from public.menu_categories
where id not in (select id from synorra_menu_categories);

commit;

notify pgrst, 'reload schema';
