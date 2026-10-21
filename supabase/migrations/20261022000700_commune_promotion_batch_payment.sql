create table if not exists public.commune_promotion_batches (
  batch_id uuid primary key,
  event_host text not null default '',
  discount_type text not null check (discount_type in ('percent', 'amount', 'item')),
  discount_value numeric(10,2) not null check (discount_value > 0),
  expires_at timestamptz not null,
  voucher_count integer not null default 0 check (voucher_count >= 0),
  approval_status text not null default 'pending'
    check (approval_status in ('pending', 'approved', 'declined')),
  payment_status text not null default 'not_paid'
    check (payment_status in ('not_paid', 'paid')),
  ready boolean not null default false,
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  check (discount_type <> 'percent' or discount_value <= 100),
  check (discount_type <> 'item' or (discount_value = trunc(discount_value) and discount_value <= 99))
);

insert into public.commune_promotion_batches (
  batch_id,
  event_host,
  discount_type,
  discount_value,
  expires_at,
  voucher_count,
  approval_status,
  ready,
  created_at
)
select
  batch_id,
  coalesce(max(event_host), ''),
  max(discount_type),
  max(discount_value),
  max(expires_at),
  count(*)::integer,
  case
    when bool_and(approval_status = 'approved') then 'approved'
    when bool_and(approval_status = 'declined') then 'declined'
    else 'pending'
  end,
  bool_and(batch_ready),
  min(created_at)
from public.commune_promotions
where batch_id is not null
group by batch_id
on conflict (batch_id) do nothing;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'commune_promotions_batch_id_fkey'
      and conrelid = 'public.commune_promotions'::regclass
  ) then
    alter table public.commune_promotions
      add constraint commune_promotions_batch_id_fkey
      foreign key (batch_id) references public.commune_promotion_batches(batch_id);
  end if;
end;
$$;

create index if not exists commune_promotion_batches_status_created_idx
  on public.commune_promotion_batches(approval_status, created_at desc)
  where ready;

alter table public.commune_promotion_batches enable row level security;
revoke all on public.commune_promotion_batches from public, anon, authenticated;
grant select, insert, update, delete on public.commune_promotion_batches to service_role;

create or replace function public.review_commune_promotion_batch(p_batch_id uuid, p_status text)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  changed_count integer;
begin
  if p_status is null or p_status not in ('approved', 'declined') then
    raise exception 'Invalid Commune promotion review status';
  end if;

  update public.commune_promotion_batches
  set approval_status = p_status,
      reviewed_at = now()
  where batch_id = p_batch_id
    and ready
    and approval_status = 'pending';

  get diagnostics changed_count = row_count;
  if changed_count = 0 then
    return 0;
  end if;

  update public.commune_promotions
  set approval_status = p_status
  where batch_id = p_batch_id
    and approval_status = 'pending';

  get diagnostics changed_count = row_count;
  return changed_count;
end;
$$;

create or replace function public.set_commune_promotion_batch_payment_status(
  p_batch_id uuid,
  p_payment_status text
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  changed_count integer;
begin
  if p_payment_status is null or p_payment_status not in ('not_paid', 'paid') then
    raise exception 'Invalid Commune promotion payment status';
  end if;

  update public.commune_promotion_batches
  set payment_status = p_payment_status
  where batch_id = p_batch_id
    and ready;

  get diagnostics changed_count = row_count;
  return changed_count;
end;
$$;

revoke all on function public.review_commune_promotion_batch(uuid, text)
  from public, anon, authenticated;
grant execute on function public.review_commune_promotion_batch(uuid, text)
  to service_role;
revoke all on function public.set_commune_promotion_batch_payment_status(uuid, text)
  from public, anon, authenticated;
grant execute on function public.set_commune_promotion_batch_payment_status(uuid, text)
  to service_role;

notify pgrst, 'reload schema';
