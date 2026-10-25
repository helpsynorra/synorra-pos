create table if not exists public.admin_ledger_entries (
  id text primary key,
  owner_id text not null,
  kind text not null check (kind in ('expense', 'credit')),
  title text not null,
  reason text not null default '',
  amount numeric not null check (amount > 0),
  entry_date date not null default current_date,
  created_at timestamptz not null default now(),
  category text not null default 'other',
  status text not null default 'unpaid',
  counterparty text,
  payment_source text not null default 'unassigned',
  related_record_id text
);

alter table public.admin_ledger_entries
  add column if not exists category text not null default 'other',
  add column if not exists status text not null default 'unpaid',
  add column if not exists counterparty text,
  add column if not exists payment_source text not null default 'unassigned',
  add column if not exists related_record_id text;

create unique index if not exists admin_ledger_owner_related_record_uidx
  on public.admin_ledger_entries(owner_id, related_record_id)
  where related_record_id is not null;

alter table public.inventory_items
  add column if not exists reorder_threshold numeric not null default 0;

alter table public.restocks
  add column if not exists unit_cost numeric;

alter table public.pos_state
  add column if not exists cash_drawer_opening_float numeric not null default 0,
  add column if not exists attendance_auth_mode text not null default 'username_password'
    check (attendance_auth_mode in ('username_password', 'photo_username_password', 'photo_full_name_pin'));

alter table public.login_activity
  add column if not exists photo_path text;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('attendance-photos', 'attendance-photos', false, 2097152, array['image/jpeg'])
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

alter table public.staff_users
  add column if not exists hourly_rate numeric,
  add column if not exists daily_rate numeric,
  add column if not exists overtime_rate numeric not null default 1.5;

create table if not exists public.work_shifts (
  id text primary key,
  owner_id text not null,
  shift_name text not null,
  shift_date date not null,
  start_time time not null,
  end_time time not null,
  opening_float numeric not null default 0 check (opening_float >= 0),
  staff_user_ids text[] not null default '{}',
  created_by_user_id text not null,
  created_at timestamptz not null default now(),
  closing_cash numeric check (closing_cash >= 0),
  closed_at timestamptz,
  closed_by_user_id text
);

create index if not exists work_shifts_owner_date_idx
  on public.work_shifts(owner_id, shift_date, start_time);

alter table public.admin_ledger_entries
  add column if not exists work_shift_id text references public.work_shifts(id) on delete set null;

create table if not exists public.payroll_records (
  id text primary key,
  owner_id text not null,
  user_id text not null,
  staff_name text not null,
  period_start date not null,
  period_end date not null,
  hours numeric not null,
  gross_pay numeric not null,
  cash_advance numeric not null default 0,
  tardiness_deduction numeric not null default 0,
  net_pay numeric not null,
  status text not null default 'unpaid' check (status in ('unpaid', 'paid')),
  payout_ledger_id text,
  paid_at timestamptz,
  unique (owner_id, user_id, period_start, period_end)
);

create or replace function public.sync_restock_expense()
returns trigger
language plpgsql
as $$
declare
  v_owner_id text;
  v_item_cost numeric;
  v_unit_size numeric;
  v_amount numeric;
  v_should_sync boolean := true;
begin
  if tg_op = 'DELETE' then
    delete from public.admin_ledger_entries
    where owner_id = old.owner_id
      and related_record_id = 'restock:' || old.id;
    return old;
  end if;

  if tg_op = 'UPDATE' then
    v_should_sync :=
      new.inventory_item_id is distinct from old.inventory_item_id or
      new.item_name_snapshot is distinct from old.item_name_snapshot or
      new.quantity_added is distinct from old.quantity_added or
      new.purchase_qty is distinct from old.purchase_qty or
      new.purchase_unit is distinct from old.purchase_unit or
      new.created_at is distinct from old.created_at or
      new.unit_cost is distinct from old.unit_cost;
    if not v_should_sync then return new; end if;
  end if;

  v_owner_id := coalesce(new.owner_id, current_setting('synorra.owner_id', true));
  if new.unit_cost is null and
     (tg_op = 'INSERT' or old.unit_cost is null) and
     new.inventory_item_id is not null then
    select cost, purchase_unit_size
      into v_item_cost, v_unit_size
      from public.inventory_items
      where id = new.inventory_item_id and owner_id = v_owner_id;
    new.unit_cost := coalesce(v_item_cost, 0);
  elsif new.inventory_item_id is not null then
    select purchase_unit_size
      into v_unit_size
      from public.inventory_items
      where id = new.inventory_item_id and owner_id = v_owner_id;
  end if;

  v_amount := coalesce(new.purchase_qty, new.quantity_added / nullif(v_unit_size, 0))
    * coalesce(new.unit_cost, 0);
  if v_amount > 0 then
    insert into public.admin_ledger_entries (
      id, owner_id, kind, title, reason, amount, entry_date, category,
      status, payment_source, related_record_id
    ) values (
      'restock-expense-' || new.id, v_owner_id, 'expense',
      'Restock: ' || new.item_name_snapshot, 'Inventory restock purchase',
      round(v_amount, 2), (new.created_at at time zone 'Asia/Manila')::date,
      'restock', 'settled', 'cash', 'restock:' || new.id
    )
    on conflict (owner_id, related_record_id) where related_record_id is not null
    do update set title = excluded.title, amount = excluded.amount,
      entry_date = excluded.entry_date, category = excluded.category,
      status = excluded.status;
  else
    delete from public.admin_ledger_entries
    where owner_id = v_owner_id and related_record_id = 'restock:' || new.id;
  end if;
  return new;
end;
$$;

drop trigger if exists restocks_sync_finance_expense on public.restocks;
create trigger restocks_sync_finance_expense
before insert or update or delete on public.restocks
for each row execute function public.sync_restock_expense();

create index if not exists payroll_records_owner_period_idx
  on public.payroll_records(owner_id, period_start, period_end);

grant select, insert, update, delete on public.payroll_records to service_role;
grant select, insert, update, delete on public.admin_ledger_entries to service_role;

notify pgrst, 'reload schema';
