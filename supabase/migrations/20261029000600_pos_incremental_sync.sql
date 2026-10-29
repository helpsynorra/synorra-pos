-- Ordered, tenant-scoped change feed for the POS client. The feed is append
-- only: physical deletes and soft deletes are both represented explicitly.
create table if not exists public.pos_sync_changes (
  id bigint generated always as identity primary key,
  owner_id text not null,
  table_name text not null,
  record_id text not null,
  operation text not null check (operation in ('upsert', 'delete')),
  row_data jsonb not null
);

create index if not exists pos_sync_changes_owner_id_id_idx
  on public.pos_sync_changes (owner_id, id);

alter table public.pos_sync_changes enable row level security;
revoke all on public.pos_sync_changes from public, anon, authenticated;
grant select, insert on public.pos_sync_changes to service_role;
grant usage, select on sequence public.pos_sync_changes_id_seq to service_role;

create or replace function public.capture_pos_sync_change()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_old jsonb;
  v_new jsonb;
  v_old_sync_data jsonb := '{}'::jsonb;
  v_new_sync_data jsonb := '{}'::jsonb;
  v_old_owner_id text;
  v_new_owner_id text;
begin
  if tg_op <> 'INSERT' then
    v_old := to_jsonb(old);
  end if;
  if tg_op <> 'DELETE' then
    v_new := to_jsonb(new);
  end if;

  v_old_owner_id := v_old->>'owner_id';
  v_new_owner_id := v_new->>'owner_id';
  v_old_sync_data := case tg_table_name
    when 'order_items' then jsonb_build_object('order_id', v_old->>'order_id')
    when 'recipes' then jsonb_build_object('menu_item_id', v_old->>'menu_item_id')
    when 'recipe_costing_menu_items' then jsonb_build_object('recipe_costing_id', v_old->>'recipe_costing_id')
    when 'recipe_costing_ingredients' then jsonb_build_object('recipe_costing_id', v_old->>'recipe_costing_id')
    else '{}'::jsonb
  end;
  v_new_sync_data := case tg_table_name
    when 'order_items' then jsonb_build_object('order_id', v_new->>'order_id')
    when 'recipes' then jsonb_build_object('menu_item_id', v_new->>'menu_item_id')
    when 'recipe_costing_menu_items' then jsonb_build_object('recipe_costing_id', v_new->>'recipe_costing_id')
    when 'recipe_costing_ingredients' then jsonb_build_object('recipe_costing_id', v_new->>'recipe_costing_id')
    else '{}'::jsonb
  end;

  if tg_op = 'INSERT' then
    if v_new_owner_id is null or btrim(v_new_owner_id) = '' then return new; end if;
    perform pg_advisory_xact_lock(hashtextextended('synorra_pos_sync:' || v_new_owner_id, 0));
    insert into public.pos_sync_changes (owner_id, table_name, record_id, operation, row_data)
    values (v_new_owner_id, tg_table_name, coalesce(v_new->>'id', v_new->>'code'), 'upsert', v_new_sync_data);
    return new;
  elsif tg_op = 'DELETE' then
    if v_old_owner_id is null or btrim(v_old_owner_id) = '' then return old; end if;
    perform pg_advisory_xact_lock(hashtextextended('synorra_pos_sync:' || v_old_owner_id, 0));
    insert into public.pos_sync_changes (owner_id, table_name, record_id, operation, row_data)
    values (v_old_owner_id, tg_table_name, coalesce(v_old->>'id', v_old->>'code'), 'delete', v_old_sync_data);
    return old;
  end if;

  if v_old_owner_id is not null and v_new_owner_id is not null
      and v_old_owner_id <> v_new_owner_id then
    perform pg_advisory_xact_lock(hashtextextended(
      'synorra_pos_sync:' || least(v_old_owner_id, v_new_owner_id), 0
    ));
    perform pg_advisory_xact_lock(hashtextextended(
      'synorra_pos_sync:' || greatest(v_old_owner_id, v_new_owner_id), 0
    ));
  elsif v_old_owner_id is not null then
    perform pg_advisory_xact_lock(hashtextextended('synorra_pos_sync:' || v_old_owner_id, 0));
  elsif v_new_owner_id is not null then
    perform pg_advisory_xact_lock(hashtextextended('synorra_pos_sync:' || v_new_owner_id, 0));
  end if;

  if v_old_owner_id is not null and btrim(v_old_owner_id) <> '' then
    insert into public.pos_sync_changes (owner_id, table_name, record_id, operation, row_data)
    values (v_old_owner_id, tg_table_name, coalesce(v_old->>'id', v_old->>'code'), 'delete', v_old_sync_data);
  end if;
  if v_new_owner_id is not null and btrim(v_new_owner_id) <> '' then
    insert into public.pos_sync_changes (owner_id, table_name, record_id, operation, row_data)
    values (v_new_owner_id, tg_table_name, coalesce(v_new->>'id', v_new->>'code'), 'upsert', v_new_sync_data);
  end if;
  return new;
end;
$$;

-- Fail closed if a deployment has not applied the tenant-isolation schema.
-- Trigger installation must never silently omit a table or tenant key.
do $$
declare
  v_table text;
  v_missing text;
  v_id_column text;
  v_tables text[] := array[
    'staff_users', 'menu_categories', 'menu_items', 'inventory_items',
    'orders', 'order_items', 'usage_logs', 'restocks', 'recipes',
    'recipe_costings', 'recipe_costing_menu_items',
    'recipe_costing_ingredients', 'login_activity', 'void_requests',
    'promotions', 'pos_state'
  ];
begin
  foreach v_table in array v_tables loop
    if to_regclass('public.' || v_table) is null then
      raise exception 'POS incremental sync requires public.% to exist', v_table;
    end if;
    v_id_column := case when v_table = 'promotions' then 'code' else 'id' end;
    select string_agg(required.column_name, ', ' order by required.column_name)
      into v_missing
      from (values (v_id_column), ('owner_id')) as required(column_name)
     where not exists (
       select 1
         from information_schema.columns c
        where c.table_schema = 'public'
          and c.table_name = v_table
          and c.column_name = required.column_name
     );
    if v_missing is not null then
      raise exception 'POS incremental sync requires public.%.% columns', v_table, v_missing;
    end if;

    execute format('drop trigger if exists capture_pos_sync_change on public.%I', v_table);
    execute format(
      'create trigger capture_pos_sync_change
       after insert or update or delete on public.%I
       for each row execute function public.capture_pos_sync_change()',
      v_table
    );
  end loop;
end;
$$;

create or replace function public.pos_sync_current_cursor(p_owner_id text)
returns text
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  perform pg_advisory_xact_lock(hashtextextended('synorra_pos_sync:' || p_owner_id, 0));
  return coalesce(
    (select max(id)::text from public.pos_sync_changes where owner_id = p_owner_id),
    '0'
  );
end;
$$;

create or replace function public.pos_sync_read_changes(
  p_owner_id text,
  p_after_id bigint,
  p_limit integer default 1000
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_events jsonb;
  v_last_id bigint;
  v_has_more boolean;
begin
  if p_owner_id is null or btrim(p_owner_id) = '' then
    raise exception 'p_owner_id is required';
  end if;
  if p_limit < 1 or p_limit > 2000 then
    raise exception 'p_limit must be between 1 and 2000';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('synorra_pos_sync:' || p_owner_id, 0));

  select coalesce(
           jsonb_agg(jsonb_build_object(
             'eventId', page.id::text,
             'tableName', page.table_name,
             'recordId', page.record_id,
             'operation', page.operation,
             'rowData', page.row_data
           ) order by page.id),
           '[]'::jsonb
         ),
         max(page.id)
    into v_events, v_last_id
    from (
      select id, table_name, record_id, operation, row_data
        from public.pos_sync_changes
       where owner_id = p_owner_id
         and id > coalesce(p_after_id, 0)
       order by id
       limit p_limit
    ) page;

  select exists (
    select 1 from public.pos_sync_changes
     where owner_id = p_owner_id and id > coalesce(v_last_id, p_after_id, 0)
  ) into v_has_more;

  return jsonb_build_object(
    'events', v_events,
    'cursor', coalesce(v_last_id::text, coalesce(p_after_id, 0)::text),
    'hasMore', v_has_more
  );
end;
$$;

revoke all on function public.capture_pos_sync_change() from public, anon, authenticated;
revoke all on function public.pos_sync_current_cursor(text) from public, anon, authenticated;
revoke all on function public.pos_sync_read_changes(text, bigint, integer) from public, anon, authenticated;
grant execute on function public.pos_sync_current_cursor(text) to service_role;
grant execute on function public.pos_sync_read_changes(text, bigint, integer) to service_role;

notify pgrst, 'reload schema';
