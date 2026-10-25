-- Waste records intentionally have no sales ticket. The atomic order writer
-- stores NULL for their ticket_no and does not advance the sales ticket
-- sequence, so the column must allow ticketless rows.
alter table public.orders
  alter column ticket_no drop not null;
