-- Keep legacy one-free-item codes valid while storing the free quantity on new codes.
update public.promotions
set discount_value = 1
where discount_type = 'item' and discount_value = 0;

alter table public.promotions
  drop constraint if exists promotions_discount_type_check,
  drop constraint if exists promotions_discount_value_check,
  drop constraint if exists promotions_code_check;

alter table public.promotions
  add constraint promotions_discount_type_check
    check (discount_type in ('percent', 'amount', 'item')),
  add constraint promotions_discount_value_check
    check (
      (discount_type = 'item'
        and discount_value between 1 and 99
        and discount_value = trunc(discount_value))
      or (discount_type <> 'item' and discount_value > 0)
    ),
  add constraint promotions_code_check
    check (code ~ '^([A-Z0-9]{6}|[A-Z0-9]{1,16}-[A-Z0-9]{6})$');

drop function if exists public.create_order_with_promo_for_owner_atomic(
  text, text, integer, text, timestamptz, text, text, jsonb, integer, integer,
  text, text, integer, text, text, integer, integer, jsonb, boolean, text, text
);

create function public.create_order_with_promo_for_owner_atomic(
  p_owner_id text,
  p_promo_code text,
  p_promo_item_index integer,
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
  p_ticket_no text,
  p_paid integer,
  p_change integer,
  p_deductions jsonb,
  p_voided boolean,
  p_void_reason text,
  p_voided_by text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_promo public.promotions%rowtype;
  v_owner_enabled boolean;
  v_expected_discount integer;
  v_selected_item jsonb;
  v_free_item_count integer;
begin
  select coalesce((permissions ->> 'promotionsEnabled')::boolean, false)
      and coalesce((permissions ->> 'promotionDiscount')::boolean, false)
    into v_owner_enabled
  from public.staff_users
  where id = p_owner_id and role = 'cashier';

  if not coalesce(v_owner_enabled, false) then
    raise exception 'PROMO_INVALID' using errcode = 'P0001';
  end if;

  select * into v_promo
  from public.promotions
  where owner_id = p_owner_id and code = upper(trim(p_promo_code))
  for update;

  if not found then
    raise exception 'PROMO_INVALID' using errcode = 'P0001';
  end if;
  if v_promo.redeemed_at is not null then
    raise exception 'PROMO_ALREADY_USED' using errcode = 'P0001';
  end if;

  if v_promo.discount_type = 'item' then
    v_free_item_count := greatest(1, v_promo.discount_value::integer);
    if p_promo_item_index is null
       or p_promo_item_index < 0
       or p_promo_item_index >= jsonb_array_length(p_items) then
      raise exception 'PROMO_INVALID' using errcode = 'P0001';
    end if;
    v_selected_item := p_items -> p_promo_item_index;
    if coalesce((v_selected_item ->> 'qty')::integer, 0) < v_free_item_count then
      raise exception 'PROMO_INVALID' using errcode = 'P0001';
    end if;
    select round(
      (
        coalesce((v_selected_item ->> 'price')::numeric, 0)
        + coalesce((
            select sum(
              coalesce((addon.value ->> 'price')::numeric, 0)
              * greatest(coalesce((addon.value ->> 'qty')::numeric, 1), 1)
            )
            from jsonb_array_elements(
              case when jsonb_typeof(v_selected_item -> 'addons') = 'array'
                then v_selected_item -> 'addons'
                else '[]'::jsonb
              end
            ) as addon(value)
          ), 0)
      ) * v_free_item_count
    )::integer into v_expected_discount;
  else
    v_expected_discount := least(
      p_subtotal,
      round(case when v_promo.discount_type = 'amount'
        then v_promo.discount_value
        else p_subtotal * v_promo.discount_value / 100
      end)::integer
    );
  end if;

  if p_discount <> v_expected_discount then
    raise exception 'PROMO_INVALID' using errcode = 'P0001';
  end if;

  update public.promotions
  set redeemed_at = now(), redeemed_order_id = p_order_id
  where owner_id = p_owner_id and code = v_promo.code;

  return public.create_order_for_owner_atomic(
    p_owner_id, p_order_id, p_created_at, p_barista_name, p_barista_user_id,
    p_items, p_subtotal, p_discount, p_promo_id, p_promo_label, p_total,
    p_payment_method, p_ticket_no, p_paid, p_change, p_deductions,
    p_voided, p_void_reason, p_voided_by
  );
end;
$$;

revoke all on function public.create_order_with_promo_for_owner_atomic(
  text, text, integer, text, timestamptz, text, text, jsonb, integer, integer,
  text, text, integer, text, text, integer, integer, jsonb, boolean, text, text
) from public, anon, authenticated;
grant execute on function public.create_order_with_promo_for_owner_atomic(
  text, text, integer, text, timestamptz, text, text, jsonb, integer, integer,
  text, text, integer, text, text, integer, integer, jsonb, boolean, text, text
) to service_role;

notify pgrst, 'reload schema';
