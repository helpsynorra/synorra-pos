alter table public.promotions
  drop constraint if exists promotions_code_check;

alter table public.promotions
  add constraint promotions_code_check
    check (code ~ '^([A-Z0-9]{6}|[A-Z0-9]{1,16}-[A-Z0-9]{6})$');

notify pgrst, 'reload schema';
