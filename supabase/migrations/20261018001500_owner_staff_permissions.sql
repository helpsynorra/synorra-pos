alter table public.staff_users
  add column if not exists permissions jsonb not null default '{}'::jsonb;

notify pgrst, 'reload schema';
