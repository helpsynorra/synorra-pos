alter table public.pos_state
  add column if not exists print_button_hidden boolean not null default false;

notify pgrst, 'reload schema';
