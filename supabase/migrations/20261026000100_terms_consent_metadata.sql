alter table public.staff_users
  add column if not exists agreed_to_terms boolean not null default false,
  add column if not exists agreed_at timestamptz;
