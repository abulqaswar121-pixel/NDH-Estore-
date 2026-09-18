begin;

create table public.payment_events (
  id uuid primary key default gen_random_uuid(),
  provider public.payment_provider not null,
  provider_event_id text not null,
  event_type text not null,
  order_id uuid references public.orders(id) on delete set null,
  payload jsonb not null,
  processed boolean not null default false,
  processing_error text,
  received_at timestamptz not null default now(),
  processed_at timestamptz,
  unique(provider,provider_event_id)
);

create index payment_events_order_idx on public.payment_events(order_id,received_at desc);
alter table public.payment_events enable row level security;
create policy payment_events_admin_read on public.payment_events for select using(public.is_admin());
revoke all on public.payment_events from anon,authenticated;

create or replace function public.mark_order_paid(target_order_id uuid, provider_reference text, paid_payload jsonb)
returns boolean
language plpgsql
security definer
set search_path=public
as $$
declare changed boolean;
begin
  update public.orders set status='paid',payment_reference=coalesce(payment_reference,provider_reference),paid_at=coalesce(paid_at,now()),payment_processing_fee=coalesce(case when paid_payload ? 'fees' then (paid_payload->>'fees')::numeric/100 when paid_payload ? 'app_fee' then (paid_payload->>'app_fee')::numeric else 0 end,0),metadata=metadata||jsonb_build_object('payment',paid_payload)
  where id=target_order_id and status='awaiting_payment';
  changed=found;
  return changed;
end $$;
revoke all on function public.mark_order_paid(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.mark_order_paid(uuid,text,jsonb) to service_role;

commit;
