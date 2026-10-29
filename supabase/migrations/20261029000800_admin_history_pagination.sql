create index if not exists usage_logs_owner_created_at_idx
  on public.usage_logs(owner_id, created_at desc);

create index if not exists restocks_owner_created_at_idx
  on public.restocks(owner_id, created_at desc);

create index if not exists login_activity_owner_at_idx
  on public.login_activity(owner_id, at desc);
