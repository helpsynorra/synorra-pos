create table if not exists public.commune_promotions (
  code text primary key
    check (code ~ '^[A-Z0-9]{1,16}-[A-Z0-9]{6}$'),
  discount_type text not null
    check (discount_type in ('percent', 'amount', 'item')),
  discount_value numeric(10,2) not null
    check (discount_value > 0),
  expires_at timestamptz not null,
  created_at timestamptz not null default now(),
  redeemed_at timestamptz,
  redeemed_order_id text,
  check (discount_type <> 'percent' or discount_value <= 100),
  check (discount_type <> 'item' or (discount_value = trunc(discount_value) and discount_value <= 99))
);

create index if not exists commune_promotions_created_idx
  on public.commune_promotions(created_at desc);

alter table public.commune_promotions enable row level security;
revoke all on public.commune_promotions from public, anon, authenticated;
grant select, insert, update, delete on public.commune_promotions to service_role;

create or replace function public.reject_expired_commune_promotion_redemption()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.redeemed_at is null
     and new.redeemed_at is not null
     and new.expires_at <= now() then
    raise exception 'PROMO_EXPIRED' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

revoke all on function public.reject_expired_commune_promotion_redemption()
  from public, anon, authenticated;

drop trigger if exists commune_promotions_reject_expired_redemption on public.commune_promotions;
create trigger commune_promotions_reject_expired_redemption
  before update of redeemed_at on public.commune_promotions
  for each row
  execute function public.reject_expired_commune_promotion_redemption();

notify pgrst, 'reload schema';
