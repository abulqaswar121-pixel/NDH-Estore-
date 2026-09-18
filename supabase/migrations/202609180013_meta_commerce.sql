begin;

grant select(meta_pixel_id) on public.vendors to anon;

create table public.meta_events (
 id uuid primary key default gen_random_uuid(),
 vendor_id uuid not null references public.vendors(id) on delete cascade,
 event_name text not null check(event_name in ('ViewContent','AddToCart','InitiateCheckout','Purchase')),
 event_id text not null,
 source_url text,
 order_id uuid references public.orders(id) on delete set null,
 payload jsonb not null default '{}'::jsonb,
 provider_response jsonb,
 status text not null default 'pending' check(status in ('pending','sent','failed','skipped')),
 failure_reason text,
 created_at timestamptz not null default now(),
 sent_at timestamptz,
 unique(vendor_id,event_id)
);
create index meta_events_vendor_created_idx on public.meta_events(vendor_id,created_at desc);
alter table public.meta_events enable row level security;
create policy meta_events_vendor_read on public.meta_events for select using(public.is_admin() or exists(select 1 from public.vendors v where v.id=vendor_id and v.owner_user_id=auth.uid()));
revoke all on public.meta_events from anon,authenticated;
grant select on public.meta_events to authenticated;

commit;
