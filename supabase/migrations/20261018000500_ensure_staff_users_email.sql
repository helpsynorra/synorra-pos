-- Repair deployments where the cashier email migration was recorded as
-- applied but the column is still missing from staff_users.
alter table public.staff_users
  add column if not exists email text,
  add column if not exists password_changed boolean not null default false;

create unique index if not exists staff_users_email_unique
  on public.staff_users (lower(email))
  where email is not null and length(trim(email)) > 0;

notify pgrst, 'reload schema';
