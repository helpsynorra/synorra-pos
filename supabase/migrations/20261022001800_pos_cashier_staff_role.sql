-- Keep Owner accounts on the existing `cashier` role, and use a distinct
-- role for staff members who work as cashiers within an Owner's store.
alter table public.staff_users
  drop constraint if exists staff_users_role_check;

alter table public.staff_users
  add constraint staff_users_role_check
  check (role in ('admin', 'cashier', 'barista', 'pos_cashier'));

notify pgrst, 'reload schema';
