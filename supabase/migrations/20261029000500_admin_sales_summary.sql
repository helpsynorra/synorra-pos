create index if not exists order_items_owner_order_id_idx
  on public.order_items(owner_id, order_id);

create index if not exists orders_owner_created_at_idx
  on public.orders(owner_id, created_at desc)
  where deleted_at is null;

create or replace function public.admin_sales_summary(
  p_owner_id text,
  p_from date,
  p_to date
)
returns jsonb
language sql
security definer
set search_path = public
as $$
  with selected_orders as (
    select
      o.id,
      o.created_at,
      o.total,
      o.subtotal,
      o.discount,
      o.payment_method
    from public.orders o
    where o.owner_id = p_owner_id
      and o.created_at >= (p_from::timestamp at time zone 'Asia/Manila')
      and o.created_at < ((p_to + 1)::timestamp at time zone 'Asia/Manila')
      and o.deleted_at is null
      and not coalesce(o.voided, false)
      and lower(coalesce(o.payment_method, '')) <> 'waste'
      and lower(coalesce(o.record_type, '')) <> 'waste'
      and lower(o.id) not like 'waste-%'
  ),
  line_rows as (
    select
      o.id as order_id,
      o.created_at,
      o.total,
      coalesce(nullif(o.subtotal, 0), o.total + coalesce(o.discount, 0)) as expected_subtotal,
      oi.product_id_snapshot as product_id,
      oi.name_snapshot as product_name,
      coalesce(nullif(trim(oi.category_snapshot), ''), mc.name, 'Other') as category,
      coalesce(nullif(trim(oi.category_type_snapshot), ''), mc.type, 'Other') as category_type,
      greatest(coalesce(oi.qty, 0), 0) as qty,
      coalesce(oi.price_snapshot, 0) as unit_price,
      lower(coalesce(oi.style, '')) as style,
      coalesce((
        select sum(
          coalesce(nullif(addon->>'price', '')::numeric, 0) *
          greatest(coalesce(nullif(addon->>'qty', '')::numeric, 1), 0)
        )
        from jsonb_array_elements(
          case when jsonb_typeof(oi.addons) = 'array' then oi.addons else '[]'::jsonb end
        ) as addon_rows(addon)
      ), 0) as addons_per_item
    from selected_orders o
    join public.order_items oi on oi.order_id = o.id
    left join public.menu_items mi
      on mi.id = coalesce(oi.menu_item_id, oi.product_id_snapshot)
     and mi.owner_id = p_owner_id
    left join public.menu_categories mc
      on mc.id = mi.category_id
     and mc.owner_id = p_owner_id
  ),
  order_line_totals as (
    select
      line_rows.*,
      sum(qty * unit_price) over (partition by order_id) as base_subtotal,
      sum(qty * addons_per_item) over (partition by order_id) as addons_subtotal
    from line_rows
  ),
  allocated_lines as (
    select
      order_id,
      created_at,
      product_id,
      product_name,
      category,
      category_type,
      qty,
      style,
      case
        when base_subtotal + addons_subtotal > 0
         and abs(expected_subtotal - (base_subtotal + addons_subtotal))
           < abs(expected_subtotal - base_subtotal)
          then (qty * unit_price + qty * addons_per_item) *
            (total::numeric / (base_subtotal + addons_subtotal))
        when base_subtotal > 0
          then (qty * unit_price) * (total::numeric / base_subtotal)
        else 0
      end as sales
    from order_line_totals
  ),
  product_rows as (
    select
      product_id as id,
      min(product_name) as name,
      min(category) as category,
      min(category_type) as category_type,
      sum(qty)::numeric as qty,
      sum(sales)::numeric as sales,
      sum(case when style = 'iced' then qty else 0 end)::numeric as iced,
      sum(case when style = 'hot' then qty else 0 end)::numeric as hot
    from allocated_lines
    group by product_id
  ),
  menu_product_rows as (
    select
      mi.id,
      mi.name,
      coalesce(mc.name, pr.category, 'Other') as category,
      coalesce(nullif(trim(mc.type), ''), pr.category_type, 'Other') as category_type,
      coalesce(pr.qty, 0) as qty,
      coalesce(pr.sales, 0) as sales,
      coalesce(pr.iced, 0) as iced,
      coalesce(pr.hot, 0) as hot
    from public.menu_items mi
    left join public.menu_categories mc
      on mc.id = mi.category_id
     and mc.owner_id = p_owner_id
    left join product_rows pr on pr.id = mi.id
    where mi.owner_id = p_owner_id
  ),
  all_products as (
    select * from menu_product_rows
    union all
    select pr.*
    from product_rows pr
    where not exists (select 1 from menu_product_rows mi where mi.id = pr.id)
  ),
  day_rows as (
    select
      (created_at at time zone 'Asia/Manila')::date as sales_date,
      count(distinct order_id)::integer as orders,
      sum(sales)::numeric as sales,
      sum(qty)::numeric as quantity
    from allocated_lines
    group by (created_at at time zone 'Asia/Manila')::date
  ),
  month_rows as (
    select
      date_trunc('month', created_at at time zone 'Asia/Manila')::date as month_date,
      count(distinct order_id)::integer as orders,
      sum(sales)::numeric as sales
    from allocated_lines
    group by date_trunc('month', created_at at time zone 'Asia/Manila')::date
  ),
  hour_rows as (
    select
      extract(hour from created_at at time zone 'Asia/Manila')::integer as hour,
      sum(qty)::numeric as quantity
    from allocated_lines
    group by extract(hour from created_at at time zone 'Asia/Manila')::integer
  ),
  payment_totals as (
    select
      case
        when lower(coalesce(payment_method, '')) like 'split:%' then 'split'
        when lower(coalesce(payment_method, '')) in ('cash', 'gcash', 'maya', 'cards', 'grab', 'foodpanda')
          then lower(payment_method)
        else 'split'
      end as method,
      count(*)::integer as count,
      sum(total)::numeric as sales
    from selected_orders
    group by 1
  ),
  payment_rows as (
    select
      methods.method,
      coalesce(totals.count, 0)::integer as count,
      coalesce(totals.sales, 0)::numeric as sales
    from (values
      (1, 'cash'),
      (2, 'gcash'),
      (3, 'maya'),
      (4, 'cards'),
      (5, 'grab'),
      (6, 'foodpanda'),
      (7, 'split')
    ) as methods(sort_order, method)
    left join payment_totals totals on totals.method = methods.method
    where methods.method <> 'split' or coalesce(totals.count, 0) > 0
  ),
  total_rows as (
    select count(*)::integer as order_count, coalesce(sum(total), 0)::numeric as sales
    from selected_orders
  )
  select jsonb_build_object(
    'totals', jsonb_build_object(
      'sales', total_rows.sales,
      'orders', total_rows.order_count,
      'averageTicket', case when total_rows.order_count = 0 then 0 else total_rows.sales / total_rows.order_count end
    ),
    'payments', coalesce((
      select jsonb_agg(jsonb_build_object('method', method, 'count', count, 'sales', sales) order by sort_order)
      from (
        select methods.sort_order, payments.method, payments.count, payments.sales
        from (values (1, 'cash'), (2, 'gcash'), (3, 'maya'), (4, 'cards'), (5, 'grab'), (6, 'foodpanda'), (7, 'split')) as methods(sort_order, method)
        join payment_rows payments on payments.method = methods.method
      ) ordered_payments
    ), '[]'::jsonb),
    'days', coalesce((
      select jsonb_agg(jsonb_build_object('date', sales_date, 'orders', orders, 'sales', sales, 'quantity', quantity) order by sales_date)
      from day_rows
    ), '[]'::jsonb),
    'months', coalesce((
      select jsonb_agg(jsonb_build_object('month', month_date, 'orders', orders, 'sales', sales) order by month_date)
      from month_rows
    ), '[]'::jsonb),
    'hours', coalesce((
      select jsonb_agg(jsonb_build_object('hour', hour, 'quantity', quantity) order by hour)
      from hour_rows
    ), '[]'::jsonb),
    'products', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', id, 'name', name, 'category', category, 'categoryType', category_type,
        'qty', qty, 'sales', sales, 'iced', iced, 'hot', hot
      ) order by name)
      from all_products
    ), '[]'::jsonb)
  )
  from total_rows;
$$;

revoke all on function public.admin_sales_summary(text, date, date) from public, anon, authenticated;
grant execute on function public.admin_sales_summary(text, date, date) to service_role;

notify pgrst, 'reload schema';
