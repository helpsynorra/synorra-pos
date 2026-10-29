-- Keep payment values selected in POS checkout valid in persisted orders.
alter table public.orders
  drop constraint if exists orders_payment_method_check;

alter table public.orders
  add constraint orders_payment_method_check
  check (
    payment_method in (
      'cash',
      'gcash',
      'maya',
      'cards',
      'grab',
      'foodpanda',
      'split',
      'waste'
    )
    or payment_method like 'split:%'
  );
