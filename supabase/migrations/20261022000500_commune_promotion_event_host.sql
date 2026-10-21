alter table public.commune_promotions
  add column if not exists event_host text not null default '';
