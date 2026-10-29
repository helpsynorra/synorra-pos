create or replace function public.admin_inventory_summary(
  p_owner_id text,
  p_from date,
  p_to date
)
returns jsonb
language sql
security definer
set search_path = public
as $$
  with bounds as (
    select
      p_from::timestamp at time zone 'Asia/Manila' as starts_at,
      (p_to + 1)::timestamp at time zone 'Asia/Manila' as ends_at
  ),
  inventory as (
    select
      i.id,
      i.name,
      i.unit,
      coalesce(i.stock, 0)::numeric as live_stock
    from public.inventory_items i
    where i.owner_id = p_owner_id
  ),
  restock_totals as (
    select
      i.id,
      coalesce(sum(r.quantity_added) filter (
        where r.created_at >= b.starts_at and r.created_at < b.ends_at
      ), 0)::numeric as restocked,
      coalesce(sum(r.quantity_added) filter (
        where r.created_at >= b.ends_at
      ), 0)::numeric as restocked_after
    from inventory i
    cross join bounds b
    left join public.restocks r
      on r.owner_id = p_owner_id
     and (
       r.inventory_item_id = i.id
       or (r.inventory_item_id is null and lower(trim(r.item_name_snapshot)) = lower(trim(i.name)))
     )
    group by i.id
  ),
  usage_totals as (
    select
      i.id,
      coalesce(sum(u.used_amount) filter (
        where u.created_at >= b.starts_at and u.created_at < b.ends_at
      ), 0)::numeric as used,
      coalesce(sum(u.used_amount) filter (
        where u.created_at >= b.ends_at
      ), 0)::numeric as used_after
    from inventory i
    cross join bounds b
    left join public.usage_logs u
      on u.owner_id = p_owner_id
     and u.item_name_snapshot <> '__usage_snapshot_empty__'
     and u.unit <> '__snapshot__'
     and (
       u.inventory_item_id = i.id
       or (u.inventory_item_id is null and lower(trim(u.item_name_snapshot)) = lower(trim(i.name)))
     )
    group by i.id
  ),
  summaries as (
    select
      i.id,
      i.name,
      i.unit,
      greatest(0, i.live_stock - r.restocked_after + u.used_after)::numeric as remaining,
      r.restocked,
      u.used
    from inventory i
    join restock_totals r on r.id = i.id
    join usage_totals u on u.id = i.id
  )
  select jsonb_build_object(
    'items',
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'inventoryItemId', id,
          'itemName', name,
          'unit', unit,
          'opening', remaining - restocked + used,
          'restocked', restocked,
          'used', used,
          'remaining', remaining
        )
        order by name
      ),
      '[]'::jsonb
    )
  )
  from summaries;
$$;

revoke all on function public.admin_inventory_summary(text, date, date)
  from public, anon, authenticated;
grant execute on function public.admin_inventory_summary(text, date, date)
  to service_role;

notify pgrst, 'reload schema';
