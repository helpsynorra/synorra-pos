create table if not exists public.staff_password_resets (
  id uuid primary key default gen_random_uuid(),
  staff_user_id text not null references public.staff_users(id) on delete cascade,
  token_hash text not null unique,
  expires_at timestamptz not null,
  used_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists staff_password_resets_staff_user_id_idx
  on public.staff_password_resets (staff_user_id);

alter table public.staff_password_resets enable row level security;
revoke all on public.staff_password_resets from anon, authenticated;
grant all on public.staff_password_resets to service_role;

notify pgrst, 'reload schema';
