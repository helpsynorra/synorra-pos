-- Remove the legacy owner RPC overload so PostgREST can resolve both
-- older clients (which omit p_waste_baristas) and current clients.
drop function if exists public.create_order_for_owner_atomic(
  text, text, timestamptz, text, text, jsonb, integer, integer, text, text,
  integer, text, text, integer, integer, jsonb, boolean, text, text
);

-- Fill the lowest unused sales ticket. This repairs gaps previously consumed
-- by waste orders while keeping allocation serialized per owner and PH day.
create or replace function public.next_ticket_no(p_at timestamptz default now())
returns text
language plpgsql
as $$
declare
  v_owner text := current_setting('synorra.owner_id', true);
  v_day date := (p_at at time zone 'Asia/Manila')::date;
  v_n integer;
begin
  if v_owner is null or v_owner = '' then
    select id into v_owner
      from public.staff_users
     where role = 'cashier'
     order by created_at nulls first, id
     limit 1;
    v_owner := coalesce(v_owner, 'cashier-1');
  end if;

  insert into public.ticket_counters(owner_id, day, n)
  values (v_owner, v_day, 0)
  on conflict (owner_id, day) do nothing;

  perform 1
    from public.ticket_counters
   where owner_id = v_owner and day = v_day
   for update;

  select candidates.ticket_no
    into v_n
    from generate_series(
      1,
      coalesce((
        select max(case
          when regexp_replace(o.ticket_no, '^#', '') ~ '^[0-9]+$'
            then regexp_replace(o.ticket_no, '^#', '')::integer
          else null
        end)
          from public.orders o
         where o.owner_id = v_owner
           and (o.created_at at time zone 'Asia/Manila')::date = v_day
           and not o.voided
           and coalesce(o.payment_method, '') <> 'waste'
           and o.id not like 'waste-%'
      ), 0) + 1
    ) as candidates(ticket_no)
   where not exists (
     select 1
       from public.orders o
      where o.owner_id = v_owner
        and (o.created_at at time zone 'Asia/Manila')::date = v_day
        and not o.voided
        and coalesce(o.payment_method, '') <> 'waste'
        and o.id not like 'waste-%'
        and case
          when regexp_replace(o.ticket_no, '^#', '') ~ '^[0-9]+$'
            then regexp_replace(o.ticket_no, '^#', '')::integer
          else null
        end = candidates.ticket_no
   )
   order by candidates.ticket_no
   limit 1;

  update public.ticket_counters
     set n = v_n
   where owner_id = v_owner and day = v_day;

  return lpad(v_n::text, 3, '0');
end;
$$;

revoke all on function public.next_ticket_no(timestamptz) from public, anon, authenticated;
grant execute on function public.next_ticket_no(timestamptz) to service_role;

notify pgrst, 'reload schema';
