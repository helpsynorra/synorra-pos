-- Manager accounts and approval-based transaction voiding are no longer used.
delete from public.staff_users
where lower(trim(username)) = 'manager'
   or lower(trim(role)) = 'manager'
   or lower(trim(title)) = 'manager';
