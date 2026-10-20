alter table public.promotions
  add column if not exists expires_at timestamptz;

create or replace function public.reject_expired_promotion_redemption()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.redeemed_at is null
     and new.redeemed_at is not null
     and new.expires_at is not null
     and new.expires_at <= now() then
    raise exception 'PROMO_EXPIRED' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

revoke all on function public.reject_expired_promotion_redemption()
  from public, anon, authenticated;

drop trigger if exists promotions_reject_expired_redemption on public.promotions;
create trigger promotions_reject_expired_redemption
  before update of redeemed_at on public.promotions
  for each row
  execute function public.reject_expired_promotion_redemption();

notify pgrst, 'reload schema';
