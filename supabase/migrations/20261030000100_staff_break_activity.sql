-- Staff breaks happen inside an open shift, so they are recorded as their own
-- attendance events instead of ending the shift. The POS uses these rows to
-- decide whether to show "Break Time" or "Resume Shift", and the admin
-- attendance log labels them instead of treating every non-login event as a
-- clock-out.
alter table public.login_activity
  drop constraint if exists login_activity_type_check;

alter table public.login_activity
  add constraint login_activity_type_check
  check (type in ('login', 'logout', 'break_start', 'break_end'));
