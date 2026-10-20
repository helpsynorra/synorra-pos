create table if not exists public.promotions (
  owner_id text not null references public.staff_users(id) on delete cascade,
  code text not null check (code ~ '^[A-Z0-9]{6}$'),
  discount_type text not null check (discount_type in ('percent', 'amount')),
  discount_value numeric(10,2) not null check (discount_value > 0),
  created_at timestamptz not null default now(),
  redeemed_at timestamptz,
  redeemed_order_id text,
  primary key (owner_id, code),
  unique (code),
  check (discount_type <> 'percent' or discount_value <= 100)
);

create index if not exists promotions_owner_created_idx
  on public.promotions(owner_id, created_at desc);

alter table public.promotions enable row level security;
revoke all on public.promotions from public, anon, authenticated;
grant select, insert, update, delete on public.promotions to service_role;

create or replace function public.create_order_with_promo_for_owner_atomic(
  p_owner_id text,
  p_promo_code text,
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

  if p_discount <> least(
    p_subtotal,
    round(case when v_promo.discount_type = 'amount'
      then v_promo.discount_value
      else p_subtotal * v_promo.discount_value / 100
    end)::integer
  ) then
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
  text, text, text, timestamptz, text, text, jsonb, integer, integer, text,
  text, integer, text, text, integer, integer, jsonb, boolean, text, text
) from public, anon, authenticated;
grant execute on function public.create_order_with_promo_for_owner_atomic(
  text, text, text, timestamptz, text, text, jsonb, integer, integer, text,
  text, integer, text, text, integer, integer, jsonb, boolean, text, text
) to service_role;

notify pgrst, 'reload schema';
