-- Store per-cup recipe amounts so changing a cup size does not overwrite
-- the ingredient quantities configured for another size.
alter table public.recipe_costings
  add column if not exists cup_recipes jsonb not null default '{}'::jsonb;

notify pgrst, 'reload schema';
