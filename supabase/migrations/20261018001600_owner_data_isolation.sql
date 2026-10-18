-- Separate each Owner's operational data. The oldest existing Owner keeps the
-- current store data; other Owner accounts receive their own independent copy
-- of the menu and start with empty sales/inventory/staff records.
do $$
declare
  v_legacy_owner_id text;
begin
  select id into v_legacy_owner_id
    from public.staff_users
   where role = 'cashier'
   order by created_at nulls first, id
   limit 1;

  if v_legacy_owner_id is null then
    v_legacy_owner_id := 'cashier-1';
  end if;

  perform set_config('synorra.legacy_owner_id', v_legacy_owner_id, false);
end;
$$;

alter table public.staff_users add column if not exists owner_id text;
alter table public.pos_state add column if not exists owner_id text;
alter table public.login_links add column if not exists owner_id text;
alter table public.menu_categories add column if not exists owner_id text;
alter table public.menu_items add column if not exists owner_id text;
alter table public.inventory_items add column if not exists owner_id text;
alter table public.orders add column if not exists owner_id text;
alter table public.order_items add column if not exists owner_id text;
alter table public.usage_logs add column if not exists owner_id text;
alter table public.restocks add column if not exists owner_id text;
alter table public.recipes add column if not exists owner_id text;
alter table public.recipe_costings add column if not exists owner_id text;
alter table public.recipe_costing_menu_items add column if not exists owner_id text;
alter table public.recipe_costing_ingredients add column if not exists owner_id text;
alter table public.login_activity add column if not exists owner_id text;
alter table public.off_requests add column if not exists owner_id text;
alter table public.void_requests add column if not exists owner_id text;
alter table if exists public.admin_ledger_entries add column if not exists owner_id text;
alter table public.ticket_counters add column if not exists owner_id text;

do $$
declare
  v_legacy_owner_id text := current_setting('synorra.legacy_owner_id', true);
  v_cashier record;
begin
  update public.staff_users
     set owner_id = case
       when role = 'cashier' then id
       when role = 'admin' then null
       else coalesce(owner_id, v_legacy_owner_id)
     end
   where owner_id is null;

  update public.pos_state set owner_id = v_legacy_owner_id where owner_id is null;
  update public.login_links set owner_id = v_legacy_owner_id where owner_id is null;
  update public.menu_categories set owner_id = v_legacy_owner_id where owner_id is null;
  update public.menu_items set owner_id = v_legacy_owner_id where owner_id is null;
  update public.inventory_items set owner_id = v_legacy_owner_id where owner_id is null;
  update public.orders set owner_id = v_legacy_owner_id where owner_id is null;
  update public.order_items set owner_id = v_legacy_owner_id where owner_id is null;
  update public.usage_logs set owner_id = v_legacy_owner_id where owner_id is null;
  update public.restocks set owner_id = v_legacy_owner_id where owner_id is null;
  update public.recipes set owner_id = v_legacy_owner_id where owner_id is null;
  update public.recipe_costings set owner_id = v_legacy_owner_id where owner_id is null;
  update public.recipe_costing_menu_items set owner_id = v_legacy_owner_id where owner_id is null;
  update public.recipe_costing_ingredients set owner_id = v_legacy_owner_id where owner_id is null;
  update public.login_activity set owner_id = v_legacy_owner_id where owner_id is null;
  update public.off_requests set owner_id = v_legacy_owner_id where owner_id is null;
  update public.void_requests set owner_id = v_legacy_owner_id where owner_id is null;
  if to_regclass('public.admin_ledger_entries') is not null then
    update public.admin_ledger_entries set owner_id = v_legacy_owner_id where owner_id is null;
  end if;
  update public.ticket_counters set owner_id = v_legacy_owner_id where owner_id is null;

  -- Keep the pre-existing singleton settings rows on the same deterministic
  -- key used by owner-scoped upserts, avoiding two rows for the legacy Owner.
  update public.pos_state
     set id = v_legacy_owner_id
   where owner_id = v_legacy_owner_id and id <> v_legacy_owner_id
     and not exists (select 1 from public.pos_state p where p.id = v_legacy_owner_id);
  update public.login_links
     set id = v_legacy_owner_id
   where owner_id = v_legacy_owner_id and id <> v_legacy_owner_id
     and not exists (select 1 from public.login_links l where l.id = v_legacy_owner_id);

  -- Each already-created Owner gets an independent menu copy with namespaced
  -- IDs. Sales, stock, restocks, and staff remain with the legacy Owner only.
  for v_cashier in
    select id from public.staff_users
     where role = 'cashier' and id <> v_legacy_owner_id
  loop
    insert into public.menu_categories (id, owner_id, name, type)
    select v_cashier.id || '--' || c.id, v_cashier.id, c.name, c.type
      from public.menu_categories c
     where c.owner_id = v_legacy_owner_id
    on conflict (id) do nothing;

    insert into public.menu_items (
      id, owner_id, name, price, category_id, image, available, types, styles, addons
    )
    select v_cashier.id || '--' || m.id,
           v_cashier.id,
           m.name,
           m.price,
           v_cashier.id || '--' || m.category_id,
           m.image,
           m.available,
           m.types,
           m.styles,
           m.addons
      from public.menu_items m
     where m.owner_id = v_legacy_owner_id
    on conflict (id) do nothing;

    insert into public.pos_state (id, owner_id, is_open, opened_at, opened_by_name,
                                  inventory_features_enabled, print_button_hidden, updated_at)
    values (v_cashier.id, v_cashier.id, false, null, null, true, false, now())
    on conflict (id) do nothing;

    insert into public.login_links (id, owner_id, admin_path, updated_at)
    select v_cashier.id, v_cashier.id, admin_path, now()
      from public.login_links
     where owner_id = v_legacy_owner_id
     limit 1
    on conflict (id) do nothing;
  end loop;
end;
$$;

create index if not exists staff_users_owner_id_idx on public.staff_users(owner_id);
create index if not exists menu_categories_owner_id_idx on public.menu_categories(owner_id);
create index if not exists menu_items_owner_id_idx on public.menu_items(owner_id);
create index if not exists inventory_items_owner_id_idx on public.inventory_items(owner_id);
create index if not exists orders_owner_id_created_at_idx on public.orders(owner_id, created_at desc);
create index if not exists order_items_owner_id_idx on public.order_items(owner_id);
create index if not exists usage_logs_owner_id_idx on public.usage_logs(owner_id);
create index if not exists restocks_owner_id_idx on public.restocks(owner_id);
create index if not exists recipes_owner_id_idx on public.recipes(owner_id);
create index if not exists recipe_costings_owner_id_idx on public.recipe_costings(owner_id);
create index if not exists recipe_costing_menu_items_owner_id_idx on public.recipe_costing_menu_items(owner_id);
create index if not exists recipe_costing_ingredients_owner_id_idx on public.recipe_costing_ingredients(owner_id);
create index if not exists login_activity_owner_id_idx on public.login_activity(owner_id);
create index if not exists off_requests_owner_id_idx on public.off_requests(owner_id);
create index if not exists void_requests_owner_id_idx on public.void_requests(owner_id);
create index if not exists ticket_counters_owner_day_idx on public.ticket_counters(owner_id, day);
alter table public.ticket_counters drop constraint if exists ticket_counters_pkey;
alter table public.ticket_counters add constraint ticket_counters_pkey primary key (owner_id, day);

notify pgrst, 'reload schema';

-- Scoped RPC entry points set a transaction-local tenant before invoking the
-- existing atomic business logic, so its order, stock, restock, and audit rows
-- are committed under the same Owner.
create or replace function public.apply_owner_scope()
returns trigger language plpgsql as $$
declare v_owner text := nullif(current_setting('synorra.owner_id', true), '');
begin
  if TG_OP = 'INSERT' then
    if v_owner is not null then new.owner_id := v_owner; end if;
    return new;
  end if;
  if v_owner is not null and old.owner_id is distinct from v_owner then
    raise exception 'OWNER_SCOPE_VIOLATION';
  end if;
  if TG_OP = 'UPDATE' then
    if v_owner is not null then new.owner_id := v_owner; end if;
    return new;
  end if;
  return old;
end $$;

do $$
declare v_table text;
begin
  foreach v_table in array array[
    'staff_users','pos_state','login_links','menu_categories','menu_items',
    'inventory_items','orders','order_items','usage_logs','restocks','recipes',
    'recipe_costings','recipe_costing_menu_items','recipe_costing_ingredients',
    'login_activity','off_requests','void_requests','ticket_counters'
  ] loop
    execute format('drop trigger if exists owner_scope_guard on public.%I', v_table);
    execute format('create trigger owner_scope_guard before insert or update or delete on public.%I for each row execute function public.apply_owner_scope()', v_table);
  end loop;
  if to_regclass('public.admin_ledger_entries') is not null then
    execute 'drop trigger if exists owner_scope_guard on public.admin_ledger_entries';
    execute 'create trigger owner_scope_guard before insert or update or delete on public.admin_ledger_entries for each row execute function public.apply_owner_scope()';
  end if;
end $$;

create or replace function public.next_ticket_no(p_at timestamptz default now())
returns text language plpgsql as $$
declare
  v_owner text := current_setting('synorra.owner_id', true);
  v_day date := (p_at at time zone 'Asia/Manila')::date;
  v_n integer;
  v_reusable integer;
begin
  if v_owner is null or v_owner = '' then
    select id into v_owner from public.staff_users where role = 'cashier' order by created_at nulls first, id limit 1;
    v_owner := coalesce(v_owner, 'cashier-1');
  end if;
  insert into public.ticket_counters(owner_id, day, n) values(v_owner, v_day, 0)
    on conflict(owner_id, day) do nothing;
  select min(case when regexp_replace(o.ticket_no, '^#', '') ~ '^[0-9]+$' then regexp_replace(o.ticket_no, '^#', '')::integer else null end)
    into v_reusable from public.orders o
   where o.owner_id = v_owner and (o.created_at at time zone 'Asia/Manila')::date = v_day and o.voided
     and not exists (
       select 1 from public.orders a where a.owner_id = v_owner
        and (a.created_at at time zone 'Asia/Manila')::date = v_day and not a.voided
        and case when regexp_replace(a.ticket_no, '^#', '') ~ '^[0-9]+$' then regexp_replace(a.ticket_no, '^#', '')::integer else null end
          = case when regexp_replace(o.ticket_no, '^#', '') ~ '^[0-9]+$' then regexp_replace(o.ticket_no, '^#', '')::integer else null end
     );
  if v_reusable is not null then
    v_n := v_reusable;
  else
    select coalesce(max(case when regexp_replace(ticket_no, '^#', '') ~ '^[0-9]+$' then regexp_replace(ticket_no, '^#', '')::integer else null end), 0) + 1
      into v_n from public.orders
     where owner_id = v_owner and (created_at at time zone 'Asia/Manila')::date = v_day;
  end if;
  update public.ticket_counters set n = v_n where owner_id = v_owner and day = v_day;
  return lpad(v_n::text, 3, '0');
end $$;

create or replace function public.create_order_for_owner_atomic(
  p_owner_id text, p_order_id text, p_created_at timestamptz,
  p_barista_name text, p_barista_user_id text, p_items jsonb,
  p_subtotal integer, p_discount integer, p_promo_id text, p_promo_label text,
  p_total integer, p_payment_method text, p_ticket_no text default null,
  p_paid integer default 0, p_change integer default 0,
  p_deductions jsonb default '[]'::jsonb, p_voided boolean default false,
  p_void_reason text default null, p_voided_by text default null
) returns jsonb language plpgsql as $$
begin
  perform set_config('synorra.owner_id', p_owner_id, true);
  return public.create_order_atomic(p_order_id,p_created_at,p_barista_name,p_barista_user_id,p_items,p_subtotal,p_discount,p_promo_id,p_promo_label,p_total,p_payment_method,p_ticket_no,p_paid,p_change,p_deductions,p_voided,p_void_reason,p_voided_by);
end $$;

create or replace function public.void_order_for_owner_atomic(p_owner_id text,p_order_id text,p_reason text,p_voided_by text)
returns jsonb language plpgsql as $$ begin
  perform set_config('synorra.owner_id',p_owner_id,true);
  return public.void_order_atomic(p_order_id,p_reason,p_voided_by);
end $$;

create or replace function public.delete_order_for_owner_atomic(p_owner_id text,p_order_id text)
returns jsonb language plpgsql as $$ begin
  perform set_config('synorra.owner_id',p_owner_id,true);
  return public.delete_order_atomic(p_order_id);
end $$;

create or replace function public.create_restock_for_owner_atomic(
  p_owner_id text,p_id text,p_inventory_item_id text,p_item_name_snapshot text,
  p_quantity_added numeric,p_created_at timestamptz,p_purchase_qty numeric default null,p_purchase_unit text default null
) returns jsonb language plpgsql as $$ begin
  perform set_config('synorra.owner_id',p_owner_id,true);
  return public.create_restock_atomic(p_id,p_inventory_item_id,p_item_name_snapshot,p_quantity_added,p_created_at,p_purchase_qty,p_purchase_unit);
end $$;

create or replace function public.edit_restock_for_owner_atomic(
  p_owner_id text,p_id text,p_old_inventory_item_id text,p_old_quantity numeric,
  p_new_inventory_item_id text,p_new_item_name_snapshot text,p_new_quantity numeric,
  p_new_created_at timestamptz,p_new_purchase_qty numeric default null,p_new_purchase_unit text default null
) returns jsonb language plpgsql as $$ begin
  perform set_config('synorra.owner_id',p_owner_id,true);
  return public.edit_restock_atomic(p_id,p_old_inventory_item_id,p_old_quantity,p_new_inventory_item_id,p_new_item_name_snapshot,p_new_quantity,p_new_created_at,p_new_purchase_qty,p_new_purchase_unit);
end $$;

create or replace function public.delete_restock_for_owner_atomic(p_owner_id text,p_id text,p_inventory_item_id text,p_quantity_added numeric)
returns jsonb language plpgsql as $$ begin
  perform set_config('synorra.owner_id',p_owner_id,true);
  return public.delete_restock_atomic(p_id,p_inventory_item_id,p_quantity_added);
end $$;

create or replace function public.save_recipe_costing_for_owner(p_owner_id text,p_id text,p_name text,p_hot_cup_inventory_item_id text,p_iced_cup_inventory_item_id text,p_other_cup_inventory_item_id text,p_menu_items jsonb,p_ingredients jsonb)
returns void language plpgsql as $$ begin
  perform set_config('synorra.owner_id',p_owner_id,true);
  perform public.save_recipe_costing(p_id,p_name,p_hot_cup_inventory_item_id,p_iced_cup_inventory_item_id,p_other_cup_inventory_item_id,p_menu_items,p_ingredients);
end $$;

create or replace function public.approve_void_request_for_owner_atomic(p_owner_id text,p_request_id text,p_approved_by_id text,p_approved_by_name text,p_new_order_id text default null,p_ticket_no text default null)
returns jsonb language plpgsql as $$ begin
  perform set_config('synorra.owner_id',p_owner_id,true);
  return public.approve_void_request_atomic(p_request_id,p_approved_by_id,p_approved_by_name,p_new_order_id,p_ticket_no);
end $$;

revoke all on function public.create_order_for_owner_atomic(text,text,timestamptz,text,text,jsonb,integer,integer,text,text,integer,text,text,integer,integer,jsonb,boolean,text,text) from public,anon,authenticated;
revoke all on function public.void_order_for_owner_atomic(text,text,text,text) from public,anon,authenticated;
revoke all on function public.delete_order_for_owner_atomic(text,text) from public,anon,authenticated;
revoke all on function public.create_restock_for_owner_atomic(text,text,text,text,numeric,timestamptz,numeric,text) from public,anon,authenticated;
revoke all on function public.edit_restock_for_owner_atomic(text,text,text,numeric,text,text,numeric,timestamptz,numeric,text) from public,anon,authenticated;
revoke all on function public.delete_restock_for_owner_atomic(text,text,text,numeric) from public,anon,authenticated;
revoke all on function public.save_recipe_costing_for_owner(text,text,text,text,text,text,jsonb,jsonb) from public,anon,authenticated;
revoke all on function public.approve_void_request_for_owner_atomic(text,text,text,text,text,text) from public,anon,authenticated;
grant execute on function public.create_order_for_owner_atomic(text,text,timestamptz,text,text,jsonb,integer,integer,text,text,integer,text,text,integer,integer,jsonb,boolean,text,text) to service_role;
grant execute on function public.void_order_for_owner_atomic(text,text,text,text) to service_role;
grant execute on function public.delete_order_for_owner_atomic(text,text) to service_role;
grant execute on function public.create_restock_for_owner_atomic(text,text,text,text,numeric,timestamptz,numeric,text) to service_role;
grant execute on function public.edit_restock_for_owner_atomic(text,text,text,numeric,text,text,numeric,timestamptz,numeric,text) to service_role;
grant execute on function public.delete_restock_for_owner_atomic(text,text,text,numeric) to service_role;
grant execute on function public.save_recipe_costing_for_owner(text,text,text,text,text,text,jsonb,jsonb) to service_role;
grant execute on function public.approve_void_request_for_owner_atomic(text,text,text,text,text,text) to service_role;

notify pgrst, 'reload schema';
