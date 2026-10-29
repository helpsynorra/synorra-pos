alter table public.order_items
  add column if not exists category_snapshot text;

update public.order_items oi
set category_snapshot = mc.name
from public.menu_items mi
join public.menu_categories mc on mc.id = mi.category_id
where oi.category_snapshot is null
  and coalesce(oi.menu_item_id, oi.product_id_snapshot) = mi.id;

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
  p_voided_by text default null,
  p_waste_baristas jsonb default null
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
    voided, void_reason, voided_at, voided_by, waste_reason, waste_baristas
  )
  values (
    p_order_id, p_created_at, p_barista_name, p_barista_user_id, p_subtotal, p_discount,
    p_promo_id, p_promo_label, p_total, p_payment_method, v_ticket_no, p_paid, p_change,
    p_voided,
    case when p_voided then p_void_reason when v_is_waste then p_void_reason else null end,
    case when p_voided then now() else null end,
    case when p_voided then p_voided_by else null end,
    case when v_is_waste then p_void_reason else null end,
    case when v_is_waste and jsonb_typeof(p_waste_baristas) = 'array' then p_waste_baristas else null end
  );

  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_index := v_index + 1;
    select id into v_menu_item_id from public.menu_items where id = v_item->>'productId';
    insert into public.order_items (
      id, order_id, menu_item_id, product_id_snapshot, name_snapshot,
      category_snapshot, qty, price_snapshot, style, addons, service_mode
    )
    values (
      p_order_id || '-item-' || v_index,
      p_order_id,
      v_menu_item_id,
      v_item->>'productId',
      v_item->>'name',
      nullif(trim(v_item->>'category'), ''),
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
