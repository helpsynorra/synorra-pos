-- Add waste_reason column to orders
alter table public.orders add column if not exists waste_reason text;

-- Update next_ticket_no to exclude waste orders from sequence calculations
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
     and coalesce(o.payment_method, '') <> 'waste'
     and not exists (
       select 1 from public.orders a where a.owner_id = v_owner
        and (a.created_at at time zone 'Asia/Manila')::date = v_day and not a.voided
        and coalesce(a.payment_method, '') <> 'waste'
        and case when regexp_replace(a.ticket_no, '^#', '') ~ '^[0-9]+$' then regexp_replace(a.ticket_no, '^#', '')::integer else null end
          = case when regexp_replace(o.ticket_no, '^#', '') ~ '^[0-9]+$' then regexp_replace(o.ticket_no, '^#', '')::integer else null end
     );
  if v_reusable is not null then
    v_n := v_reusable;
  else
    select coalesce(max(case when regexp_replace(ticket_no, '^#', '') ~ '^[0-9]+$' then regexp_replace(ticket_no, '^#', '')::integer else null end), 0) + 1
      into v_n from public.orders
     where owner_id = v_owner and (created_at at time zone 'Asia/Manila')::date = v_day
       and coalesce(payment_method, '') <> 'waste';
  end if;
  update public.ticket_counters set n = v_n where owner_id = v_owner and day = v_day;
  return lpad(v_n::text, 3, '0');
end $$;

-- Update create_order_atomic to skip ticket number generation for waste orders and store waste_reason
create or replace function public.create_order_atomic(
  p_order_id text,
  p_created_at timestamptz,
  p_barista_name text,
  p_barista_user_id text,
  p_items jsonb,
  p_subtotal integer,
  p_discount integer,
  p_promo_id text,
  p_promo_label text,
  p_total integer,
  p_payment_method text,
  p_ticket_no text default null,
  p_paid integer default 0,
  p_change integer default 0,
  p_deductions jsonb default '[]'::jsonb,
  p_voided boolean default false,
  p_void_reason text default null,
  p_voided_by text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item jsonb;
  v_index integer := 0;
  v_menu_item_id text;
  v_deduction jsonb;
  v_updated_rows integer;
  v_ticket_no text;
  v_is_waste boolean := (coalesce(p_payment_method, '') = 'waste');
begin
  if p_order_id is null or length(trim(p_order_id)) = 0 then
    raise exception 'create_order_atomic: p_order_id is required';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'create_order_atomic: p_items must be a non-empty JSON array';
  end if;

  if v_is_waste then
    v_ticket_no := null;
  else
    v_ticket_no := public.next_ticket_no(p_created_at);
  end if;

  insert into public.orders (
    id, created_at, barista_name, barista_user_id, subtotal, discount,
    promo_id, promo_label, total, payment_method, ticket_no, paid, change,
    voided, void_reason, voided_at, voided_by, waste_reason
  )
  values (
    p_order_id, p_created_at, p_barista_name, p_barista_user_id, p_subtotal, p_discount,
    p_promo_id, p_promo_label, p_total, p_payment_method, v_ticket_no, p_paid, p_change,
    p_voided,
    case when p_voided then p_void_reason when v_is_waste then p_void_reason else null end,
    case when p_voided then now() else null end,
    case when p_voided then p_voided_by else null end,
    case when v_is_waste then p_void_reason else null end
  );

  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_index := v_index + 1;
    select id into v_menu_item_id from public.menu_items where id = v_item->>'productId';
    insert into public.order_items (
      id, order_id, menu_item_id, product_id_snapshot, name_snapshot,
      qty, price_snapshot, style, addons, service_mode
    )
    values (
      p_order_id || '-item-' || v_index,
      p_order_id,
      v_menu_item_id,
      v_item->>'productId',
      v_item->>'name',
      (v_item->>'qty')::integer,
      (v_item->>'price')::integer,
      nullif(v_item->>'style', ''),
      case when jsonb_typeof(v_item->'addons') = 'array' then v_item->'addons' else '[]'::jsonb end,
      case when v_item->>'serviceMode' in ('dine-in', 'take-out') then v_item->>'serviceMode' else null end
    );
  end loop;

  if p_deductions is not null and jsonb_typeof(p_deductions) = 'array' then
    for v_deduction in select * from jsonb_array_elements(p_deductions)
    loop
      if (v_deduction->>'amount')::numeric > 0 then
        update public.inventory_items
        set stock = greatest(0, stock - (v_deduction->>'amount')::numeric)
        where id = v_deduction->>'inventoryItemId'
          and stock >= (v_deduction->>'amount')::numeric;

        get diagnostics v_updated_rows = row_count;
        if v_updated_rows = 0 then
          raise exception 'INSUFFICIENT_STOCK:%', (v_deduction->>'itemName');
        end if;

        insert into public.usage_logs (
          id, order_id, order_item_id, inventory_item_id,
          item_name_snapshot, used_amount, unit, created_at
        )
        values (
          p_order_id || '-' || (v_deduction->>'inventoryItemId') || '-usage',
          p_order_id,
          nullif(v_deduction->>'orderItemId', ''),
          v_deduction->>'inventoryItemId',
          v_deduction->>'itemName',
          (v_deduction->>'amount')::numeric,
          coalesce(v_deduction->>'unit', 'pcs'),
          p_created_at
        );
      end if;
    end loop;
  end if;

  return jsonb_build_object('ok', true, 'ticketNo', v_ticket_no);
end;
$$;

