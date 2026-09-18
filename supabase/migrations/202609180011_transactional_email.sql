begin;

create type public.email_status as enum ('queued','sending','sent','failed');
create table public.email_messages (
  id uuid primary key default gen_random_uuid(),
  order_id uuid references public.orders(id) on delete cascade,
  vendor_id uuid references public.vendors(id) on delete cascade,
  template text not null check(template in ('order_confirmation','vendor_notification','payment_confirmation','order_processing','order_fulfilled','order_cancelled','order_refunded')),
  recipient_email text not null,
  recipient_name text not null default '',
  idempotency_key text not null unique,
  status public.email_status not null default 'queued',
  attempts integer not null default 0,
  provider_message_id text,
  last_error text,
  payload jsonb not null default '{}'::jsonb,
  next_attempt_at timestamptz not null default now(),
  sent_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index email_messages_dispatch_idx on public.email_messages(status,next_attempt_at) where status in ('queued','failed');
create index email_messages_order_idx on public.email_messages(order_id,created_at desc);
create trigger email_messages_updated_at before update on public.email_messages for each row execute function public.set_updated_at();
alter table public.email_messages enable row level security;
create policy email_messages_vendor_read on public.email_messages for select using(public.is_admin() or exists(select 1 from public.vendors v where v.id=vendor_id and v.owner_user_id=auth.uid()));
revoke all on public.email_messages from anon,authenticated;
grant select on public.email_messages to authenticated;

create or replace function public.queue_order_emails()
returns trigger language plpgsql security definer set search_path=public as $$
declare vendor_record public.vendors%rowtype;selected_template text;
begin
  select * into vendor_record from public.vendors where id=new.vendor_id;
  if tg_op='INSERT' then
    insert into public.email_messages(order_id,vendor_id,template,recipient_email,recipient_name,idempotency_key)
    values(new.id,new.vendor_id,'order_confirmation',new.customer_email,new.customer_name,'order:'||new.id||':confirmation') on conflict(idempotency_key) do nothing;
    insert into public.email_messages(order_id,vendor_id,template,recipient_email,recipient_name,idempotency_key)
    values(new.id,new.vendor_id,'vendor_notification',vendor_record.email,vendor_record.business_name,'order:'||new.id||':vendor-notification') on conflict(idempotency_key) do nothing;
  elsif old.status is distinct from new.status then
    selected_template=case new.status when 'paid' then 'payment_confirmation' when 'processing' then 'order_processing' when 'fulfilled' then 'order_fulfilled' when 'cancelled' then 'order_cancelled' when 'refunded' then 'order_refunded' else null end;
    if selected_template is not null then
      insert into public.email_messages(order_id,vendor_id,template,recipient_email,recipient_name,idempotency_key)
      values(new.id,new.vendor_id,selected_template,new.customer_email,new.customer_name,'order:'||new.id||':'||selected_template) on conflict(idempotency_key) do nothing;
    end if;
  end if;
  return new;
end $$;
create trigger queue_order_email_on_create after insert on public.orders for each row execute function public.queue_order_emails();
create trigger queue_order_email_on_status after update of status on public.orders for each row execute function public.queue_order_emails();

commit;
