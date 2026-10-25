-- Waste is a valid internal order type, not a internal payment method. Allow
-- it in the existing order constraint while preserving supported sale methods.
alter table public.orders
  drop constraint if exists orders_payment_method_check;

alter table public.orders
  add constraint orders_payment_method_check
  check (
    payment_method in ('cash', 'gcash', 'maya', 'waste')
    or payment_method like 'split:%'
  );
