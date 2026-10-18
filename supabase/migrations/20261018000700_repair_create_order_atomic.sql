-- Repair deployments where the order RPC migration was skipped or the
-- PostgREST schema cache still exposes an older create_order_atomic overload.
create table if not exists public.ticket_counters (
  day date primary key,
  n integer not null
);

alter table public.ticket_counters enable row level security;
revoke all on public.ticket_counters from public, anon, authenticated;
grant select, insert, update, delete on public.ticket_counters to service_role;

create or replace function public.next_ticket_no(p_at timestamptz default now())
returns text
language plpgsql
as $$
declare
  v_day date;
  v_n integer;
  v_reusable integer;
begin
  v_day := (p_at at time zone 'Asia/Manila')::date;

  insert into public.ticket_counters (day, n)
  values (v_day, 0)
  on conflict (day) do nothing;

  select n into v_n
    from public.ticket_counters
   where day = v_day
   for update;

  select min(
           case
             when regexp_replace(o.ticket_no, '^#', '') ~ '^[0-9]+$'
               then regexp_replace(o.ticket_no, '^#', '')::integer
             else null
           end
         )
    into v_reusable
    from public.orders o
   where (o.created_at at time zone 'Asia/Manila')::date = v_day
     and o.voided
     and not exists (
       select 1
         from public.orders active_order
        where (active_order.created_at at time zone 'Asia/Manila')::date = v_day
          and not active_order.voided
          and case
                when regexp_replace(active_order.ticket_no, '^#', '') ~ '^[0-9]+$'
                  then regexp_replace(active_order.ticket_no, '^#', '')::integer
                else null
              end = case
                      when regexp_replace(o.ticket_no, '^#', '') ~ '^[0-9]+$'
                        then regexp_replace(o.ticket_no, '^#', '')::integer
                      else null
                    end
     );

  if v_reusable is not null then
    v_n := v_reusable;
  else
    select coalesce(max(
             case
               when regexp_replace(o.ticket_no, '^#', '') ~ '^[0-9]+$'
                 then regexp_replace(o.ticket_no, '^#', '')::integer
               else null
             end
           ), 0) + 1
      into v_n
      from public.orders o
     where (o.created_at at time zone 'Asia/Manila')::date = v_day;
  end if;

  update public.ticket_counters set n = v_n where day = v_day;
  return lpad(v_n::text, 3, '0');
end;
$$;

revoke all on function public.next_ticket_no(timestamptz) from public, anon, authenticated;
grant execute on function public.next_ticket_no(timestamptz) to service_role;

alter table public.order_items add column if not exists service_mode text;

-- Remove the old 17-argument overload so PostgREST cannot resolve calls
-- ambiguously after the version with p_voided_by is installed.
drop function if exists public.create_order_atomic(
  text, timestamptz, text, text, jsonb, integer, integer, text, text,
  integer, text, text, integer, integer, jsonb, boolean, text
);

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
as $$
declare
  v_item jsonb;
  v_index integer := 0;
  v_menu_item_id text;
  v_deduction jsonb;
  v_updated_rows integer;
  v_ticket_no text;
begin
  if p_order_id is null or length(trim(p_order_id)) = 0 then
    raise exception 'create_order_atomic: p_order_id is required';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'create_order_atomic: p_items must be a non-empty JSON array';
  end if;

  v_ticket_no := public.next_ticket_no(p_created_at);

  insert into public.orders (
    id, created_at, barista_name, barista_user_id, subtotal, discount,
    promo_id, promo_label, total, payment_method, ticket_no, paid, change,
    voided, void_reason, voided_at, voided_by
  )
  values (
    p_order_id, p_created_at, p_barista_name, p_barista_user_id, p_subtotal, p_discount,
    p_promo_id, p_promo_label, p_total, p_payment_method, v_ticket_no, p_paid, p_change,
    p_voided,
    case when p_voided then p_void_reason else null end,
    case when p_voided then now() else null end,
    case when p_voided then p_voided_by else null end
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

  if not p_voided and p_deductions is not null and jsonb_typeof(p_deductions) = 'array' then
    for v_deduction in select * from jsonb_array_elements(p_deductions)
    loop
      update public.inventory_items
      set stock = stock - (v_deduction->>'amount')::numeric
      where id = v_deduction->>'inventoryItemId'
        and stock >= (v_deduction->>'amount')::numeric;

      get diagnostics v_updated_rows = row_count;
      if v_updated_rows = 0 then
        raise exception 'INSUFFICIENT_STOCK:%', coalesce(v_deduction->>'itemName', v_deduction->>'inventoryItemId');
      end if;

      insert into public.usage_logs (
        id, order_id, order_item_id, inventory_item_id,
        item_name_snapshot, used_amount, unit
      )
      values (
        p_order_id || '-' || (v_deduction->>'inventoryItemId') || '-usage',
        p_order_id,
        coalesce(v_deduction->>'orderItemId', ''),
        v_deduction->>'inventoryItemId',
        v_deduction->>'itemName',
        (v_deduction->>'amount')::numeric,
        v_deduction->>'unit'
      );
    end loop;
  end if;

  return jsonb_build_object('ok', true, 'orderId', p_order_id, 'ticketNo', v_ticket_no);
end;
$$;

revoke all on function public.create_order_atomic(
  text, timestamptz, text, text, jsonb, integer, integer, text, text,
  integer, text, text, integer, integer, jsonb, boolean, text, text
) from public, anon, authenticated;
grant execute on function public.create_order_atomic(
  text, timestamptz, text, text, jsonb, integer, integer, text, text,
  integer, text, text, integer, integer, jsonb, boolean, text, text
) to service_role;

notify pgrst, 'reload schema';
