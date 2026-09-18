begin;

create table public.order_status_history (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  from_status public.order_status,
  to_status public.order_status not null,
  changed_by uuid references public.users(id) on delete set null,
  note text,
  created_at timestamptz not null default now()
);
create index order_status_history_order_idx on public.order_status_history(order_id,created_at desc);
alter table public.order_status_history enable row level security;
create policy order_history_participant_read on public.order_status_history for select using (
  exists(select 1 from public.orders o join public.vendors v on v.id=o.vendor_id where o.id=order_id and (o.customer_id=auth.uid() or v.owner_user_id=auth.uid() or public.is_admin()))
);
revoke insert,update,delete on public.order_status_history from anon,authenticated;

create or replace function public.vendor_transition_order(target_order_id uuid,new_status public.order_status,note text default null)
returns public.orders
language plpgsql
security definer
set search_path=public
as $$
declare current_order public.orders%rowtype;previous_status public.order_status;line record;allowed boolean:=false;
begin
  select o.* into current_order from public.orders o join public.vendors v on v.id=o.vendor_id
  where o.id=target_order_id and (v.owner_user_id=auth.uid() or public.is_admin()) for update;
  if not found then raise exception 'Order not found or access denied'; end if;
  previous_status=current_order.status;
  if previous_status=new_status then return current_order; end if;
  allowed=case
    when public.is_admin() then true
    when previous_status='pending' and new_status in ('processing','cancelled') then true
    when previous_status='awaiting_payment' and new_status='cancelled' then true
    when previous_status='paid' and new_status='processing' then true
    when previous_status='processing' and new_status in ('fulfilled','cancelled') then true
    else false end;
  if not allowed then raise exception 'This order status transition is not allowed'; end if;
  if new_status='cancelled' then
    if current_order.paid_at is not null then raise exception 'Paid orders must be refunded through the payment workflow'; end if;
    for line in select oi.quantity,oi.product_id,oi.variant_id,p.product_type from public.order_items oi left join public.products p on p.id=oi.product_id where oi.order_id=target_order_id
    loop
      if line.product_type='physical' then
        if line.variant_id is not null then update public.product_variants set stock_count=stock_count+line.quantity where id=line.variant_id;
        elsif line.product_id is not null then update public.products set stock_count=stock_count+line.quantity where id=line.product_id;
        end if;
      end if;
    end loop;
  end if;
  update public.orders set status=new_status where id=target_order_id returning * into current_order;
  insert into public.order_status_history(order_id,from_status,to_status,changed_by,note) values(target_order_id,previous_status,new_status,auth.uid(),nullif(trim(note),''));
  return current_order;
end $$;

grant execute on function public.vendor_transition_order(uuid,public.order_status,text) to authenticated;

commit;
