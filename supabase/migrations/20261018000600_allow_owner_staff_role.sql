alter table public.staff_users
  drop constraint if exists staff_users_role_check;

-- Earlier app versions stored Owner accounts with the Barista database role.
update public.staff_users
set role = 'cashier', title = 'Owner'
where lower(trim(role)) = 'barista'
  and lower(trim(title)) in ('owner', 'cashier', 'sale in charge');

alter table public.staff_users
  add constraint staff_users_role_check
  check (role in ('admin', 'cashier', 'barista'));

notify pgrst, 'reload schema';
