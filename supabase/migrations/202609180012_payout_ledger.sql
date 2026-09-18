begin;

create table public.payout_accounts (
  id uuid primary key default gen_random_uuid(),
  vendor_id uuid not null references public.vendors(id) on delete cascade,
  bank_code text not null,
  bank_name text not null,
  account_name text not null,
  account_number_last4 char(4) not null,
  provider_recipient_code text not null unique,
  is_default boolean not null default false,
  verified_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index payout_accounts_vendor_idx on public.payout_accounts(vendor_id);
create trigger payout_accounts_updated_at before update on public.payout_accounts for each row execute function public.set_updated_at();
alter table public.payout_accounts enable row level security;
create policy payout_accounts_owner_read on public.payout_accounts for select using(public.is_admin() or exists(select 1 from public.vendors v where v.id=vendor_id and v.owner_user_id=auth.uid()));
create policy payout_accounts_owner_insert on public.payout_accounts for insert with check(exists(select 1 from public.vendors v where v.id=vendor_id and v.owner_user_id=auth.uid()));
create policy payout_accounts_owner_update on public.payout_accounts for update using(public.is_admin() or exists(select 1 from public.vendors v where v.id=vendor_id and v.owner_user_id=auth.uid())) with check(public.is_admin() or exists(select 1 from public.vendors v where v.id=vendor_id and v.owner_user_id=auth.uid()));
create policy payout_accounts_owner_delete on public.payout_accounts for delete using(public.is_admin() or exists(select 1 from public.vendors v where v.id=vendor_id and v.owner_user_id=auth.uid()));
revoke insert,update on public.payout_accounts from authenticated;

create table public.payout_events (
  id uuid primary key default gen_random_uuid(),
  payout_id uuid not null references public.payouts(id) on delete cascade,
  event_type text not null,
  provider_event_id text,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique(provider_event_id)
);
alter table public.payout_events enable row level security;
create policy payout_events_admin_read on public.payout_events for select using(public.is_admin());
revoke all on public.payout_events from anon,authenticated;

create or replace function public.vendor_ngn_ledger(target_vendor_id uuid)
returns table(gross numeric,platform_fees numeric,processing_fees numeric,paid_out numeric,pending_payouts numeric,available numeric)
language sql
stable
security definer
set search_path=public
as $$
  with authorized as (
    select 1 from public.vendors where id=target_vendor_id and (owner_user_id=auth.uid() or public.is_admin())
  ), earnings as (
    select coalesce(sum(total),0) gross,coalesce(sum(platform_fee),0) platform_fees,coalesce(sum(payment_processing_fee),0) processing_fees
    from public.orders,authorized where vendor_id=target_vendor_id and currency='NGN' and status in ('paid','processing','fulfilled') and payment_provider in ('paystack','flutterwave','stripe')
  ), withdrawals as (
    select coalesce(sum(amount) filter(where status='paid'),0) paid_out,coalesce(sum(amount) filter(where status in ('requested','processing')),0) pending_payouts
    from public.payouts,authorized where vendor_id=target_vendor_id and currency='NGN'
  )
  select e.gross,e.platform_fees,e.processing_fees,w.paid_out,w.pending_payouts,greatest(0,e.gross-e.platform_fees-e.processing_fees-w.paid_out-w.pending_payouts)
  from earnings e cross join withdrawals w;
$$;

create or replace function public.request_vendor_payout(target_account_id uuid,requested_amount numeric)
returns public.payouts
language plpgsql
security definer
set search_path=public
as $$
declare account_record public.payout_accounts%rowtype;ledger record;created_payout public.payouts%rowtype;
begin
  if requested_amount<1000 then raise exception 'Minimum payout is NGN 1,000'; end if;
  select pa.* into account_record from public.payout_accounts pa join public.vendors v on v.id=pa.vendor_id where pa.id=target_account_id and (v.owner_user_id=auth.uid() or public.is_admin());
  if not found then raise exception 'Payout account not found'; end if;
  perform pg_advisory_xact_lock(hashtextextended(account_record.vendor_id::text,0));
  select * into ledger from public.vendor_ngn_ledger(account_record.vendor_id);
  if requested_amount>ledger.available then raise exception 'Insufficient available balance'; end if;
  insert into public.payouts(vendor_id,amount,currency,status,bank_account_snapshot)
  values(account_record.vendor_id,round(requested_amount,2),'NGN','requested',jsonb_build_object('account_id',account_record.id,'bank_code',account_record.bank_code,'bank_name',account_record.bank_name,'account_name',account_record.account_name,'account_number_last4',account_record.account_number_last4,'recipient_code',account_record.provider_recipient_code))
  returning * into created_payout;
  insert into public.payout_events(payout_id,event_type,payload) values(created_payout.id,'requested',jsonb_build_object('amount',created_payout.amount,'currency','NGN'));
  return created_payout;
end $$;

grant execute on function public.vendor_ngn_ledger(uuid) to authenticated;
grant execute on function public.request_vendor_payout(uuid,numeric) to authenticated;
revoke insert,update,delete on public.payouts from authenticated;

commit;
