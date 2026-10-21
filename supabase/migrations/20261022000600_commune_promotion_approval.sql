alter table public.commune_promotions
  add column if not exists batch_id uuid,
  add column if not exists batch_ready boolean not null default true,
  add column if not exists approval_status text not null default 'approved'
    check (approval_status in ('pending', 'approved', 'declined'));

create index if not exists commune_promotions_batch_status_idx
  on public.commune_promotions(batch_id, approval_status);

create or replace function public.review_commune_promotion_batch(p_batch_id uuid, p_status text)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  changed_count integer;
begin
  if p_status not in ('approved', 'declined') then
    raise exception 'Invalid Commune promotion review status';
  end if;

  update public.commune_promotions
  set approval_status = p_status
  where batch_id = p_batch_id
    and batch_ready
    and approval_status = 'pending';

  get diagnostics changed_count = row_count;
  return changed_count;
end;
$$;

revoke all on function public.review_commune_promotion_batch(uuid, text)
  from public, anon, authenticated;
grant execute on function public.review_commune_promotion_batch(uuid, text)
  to service_role;

notify pgrst, 'reload schema';
