-- The application reads and writes one POS status row in this table.
-- Some deployed databases do not have the original table creation migration,
-- so create it safely when missing before applying later column migrations.
create table if not exists public.pos_state (
  id text primary key,
  is_open boolean not null default false,
  opened_at timestamptz,
  opened_by_name text,
  inventory_features_enabled boolean not null default true,
  updated_at timestamptz not null default now()
);

alter table public.pos_state enable row level security;
revoke all on public.pos_state from anon, authenticated;

notify pgrst, 'reload schema';
