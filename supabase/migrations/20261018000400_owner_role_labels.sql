-- Keep Admin separate from the POS account that is displayed as Owner.
update public.staff_users
set title = 'Admin'
where lower(trim(role)) = 'admin'
  and lower(trim(title)) = 'owner';

update public.staff_users
set title = 'Owner'
where lower(trim(role)) = 'cashier'
  and lower(trim(title)) in ('cashier', 'sale in charge');
