alter table public.commune_promotion_batches
  add column if not exists event_ended_at timestamptz;

create index if not exists commune_promotion_batches_event_ended_idx
  on public.commune_promotion_batches(event_host, event_ended_at)
  where event_ended_at is not null;

create or replace function public.end_commune_promotion_event(
  p_event_host text,
  p_ended_at timestamptz default now()
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  changed_count integer;
begin
  if p_event_host is null or length(trim(p_event_host)) = 0 or p_ended_at is null then
    raise exception 'A valid Commune promotion event host and end time are required';
  end if;

  update public.commune_promotion_batches
  set event_ended_at = p_ended_at
  where event_host = trim(p_event_host)
    and event_ended_at is null;

  update public.commune_promotions
  set expires_at = p_ended_at
  where event_host = trim(p_event_host)
    and redeemed_at is null
    and expires_at > p_ended_at;

  get diagnostics changed_count = row_count;
  return changed_count;
end;
$$;

revoke all on function public.end_commune_promotion_event(text, timestamptz)
  from public, anon, authenticated;
grant execute on function public.end_commune_promotion_event(text, timestamptz)
  to service_role;

notify pgrst, 'reload schema';
