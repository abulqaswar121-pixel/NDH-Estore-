begin;

alter table public.vendors add column grace_period_end timestamptz;
alter table public.vendors add column subscription_last_checked_at timestamptz;
update public.vendors set grace_period_end=current_period_end+interval '7 days' where subscription_status in ('active','past_due') and grace_period_end is null;

create or replace function public.vendor_has_platform_access(target_vendor_id uuid)
returns boolean
language sql
stable
security definer
set search_path=public
as $$
  select coalesce((
    select case
      when subscription_status='trial' then now()<=trial_end_date
      when subscription_status='active' then now()<=current_period_end
      when subscription_status='past_due' then grace_period_end is not null and now()<=grace_period_end
      else false end
    from public.vendors where id=target_vendor_id
  ),false);
$$;

create or replace function public.effective_subscription_status(target_vendor_id uuid)
returns public.subscription_status
language sql
stable
security definer
set search_path=public
as $$
  select coalesce((
    select case
      when subscription_status='trial' and now()<=trial_end_date then 'trial'::public.subscription_status
      when subscription_status='active' and now()<=current_period_end then 'active'::public.subscription_status
      when subscription_status in ('active','past_due') and grace_period_end is not null and now()<=grace_period_end then 'past_due'::public.subscription_status
      else 'expired'::public.subscription_status end
    from public.vendors where id=target_vendor_id
  ),'expired'::public.subscription_status);
$$;

grant execute on function public.effective_subscription_status(uuid) to anon,authenticated;
grant execute on function public.vendor_has_platform_access(uuid) to anon,authenticated;

create or replace function public.enforce_order_subscription_access()
returns trigger language plpgsql set search_path=public as $$
declare vendor_tier public.subscription_tier;
begin
  if not public.vendor_has_platform_access(new.vendor_id) then raise exception 'Vendor subscription is not active'; end if;
  select subscription_tier into vendor_tier from public.vendors where id=new.vendor_id;
  if new.currency<>'NGN' and vendor_tier<>'global_enterprise' then raise exception 'International checkout requires Global Enterprise'; end if;
  return new;
end $$;
create trigger orders_require_vendor_access before insert on public.orders for each row execute function public.enforce_order_subscription_access();

create or replace function public.refresh_vendor_subscription(target_vendor_id uuid)
returns public.subscription_status
language plpgsql
security definer
set search_path=public
as $$
declare effective public.subscription_status;owner_id uuid;
begin
  select owner_user_id into owner_id from public.vendors where id=target_vendor_id;
  if owner_id is null or (owner_id<>auth.uid() and not public.is_admin() and auth.role()<>'service_role') then raise exception 'Access denied'; end if;
  effective=public.effective_subscription_status(target_vendor_id);
  update public.vendors set subscription_status=effective,subscription_last_checked_at=now() where id=target_vendor_id and subscription_status<>effective;
  return effective;
end $$;
grant execute on function public.refresh_vendor_subscription(uuid) to authenticated,service_role;

-- Prevent vendors from changing subscription, fees, ownership, or private tracking credentials directly.
revoke update on public.vendors from authenticated;
grant update(business_name,email,whatsapp_number,business_category,business_description,support_email,address,social_links,design_settings,default_currency,timezone,meta_pixel_id,seo_title,seo_description,published,updated_at) on public.vendors to authenticated;
revoke update on public.orders from authenticated;

-- Replace product access and mutation policies with subscription-aware ownership rules.
drop policy if exists products_public_read on public.products;
drop policy if exists products_owner_insert on public.products;
drop policy if exists products_owner_update on public.products;
drop policy if exists products_owner_delete on public.products;
create policy products_access_read on public.products for select using (
  public.is_admin() or (public.vendor_has_platform_access(vendor_id) and exists(select 1 from public.vendors v where v.id=vendor_id and (v.published or v.owner_user_id=auth.uid())))
);
create policy products_owner_insert on public.products for insert with check (public.vendor_has_platform_access(vendor_id) and exists(select 1 from public.vendors v where v.id=vendor_id and v.owner_user_id=auth.uid()));
create policy products_owner_update on public.products for update using (public.is_admin() or (public.vendor_has_platform_access(vendor_id) and exists(select 1 from public.vendors v where v.id=vendor_id and v.owner_user_id=auth.uid()))) with check (public.is_admin() or (public.vendor_has_platform_access(vendor_id) and exists(select 1 from public.vendors v where v.id=vendor_id and v.owner_user_id=auth.uid())));
create policy products_owner_delete on public.products for delete using (public.is_admin() or (public.vendor_has_platform_access(vendor_id) and exists(select 1 from public.vendors v where v.id=vendor_id and v.owner_user_id=auth.uid())));

drop policy if exists variants_public_read on public.product_variants;
drop policy if exists variants_owner_manage on public.product_variants;
create policy variants_access_read on public.product_variants for select using (public.is_admin() or exists(select 1 from public.products p join public.vendors v on v.id=p.vendor_id where p.id=product_id and public.vendor_has_platform_access(v.id) and (p.is_active and v.published or v.owner_user_id=auth.uid())));
create policy variants_owner_manage on public.product_variants for all using (public.is_admin() or exists(select 1 from public.products p join public.vendors v on v.id=p.vendor_id where p.id=product_id and v.owner_user_id=auth.uid() and public.vendor_has_platform_access(v.id))) with check (public.is_admin() or exists(select 1 from public.products p join public.vendors v on v.id=p.vendor_id where p.id=product_id and v.owner_user_id=auth.uid() and public.vendor_has_platform_access(v.id)));

drop policy if exists zones_public_read on public.shipping_zones;
drop policy if exists zones_owner_manage on public.shipping_zones;
create policy zones_access_read on public.shipping_zones for select using (public.is_admin() or (public.vendor_has_platform_access(vendor_id) and exists(select 1 from public.vendors v where v.id=vendor_id and ((active and v.published) or v.owner_user_id=auth.uid()))));
create policy zones_owner_manage on public.shipping_zones for all using (public.is_admin() or (public.vendor_has_platform_access(vendor_id) and exists(select 1 from public.vendors v where v.id=vendor_id and v.owner_user_id=auth.uid()))) with check (public.is_admin() or (public.vendor_has_platform_access(vendor_id) and exists(select 1 from public.vendors v where v.id=vendor_id and v.owner_user_id=auth.uid())));

drop policy if exists cargo_public_read on public.cargo_profiles;
drop policy if exists cargo_owner_manage on public.cargo_profiles;
create policy cargo_access_read on public.cargo_profiles for select using (public.is_admin() or (public.vendor_has_platform_access(vendor_id) and exists(select 1 from public.vendors v where v.id=vendor_id and ((active and v.published) or v.owner_user_id=auth.uid()))));
create policy cargo_owner_manage on public.cargo_profiles for all using (public.is_admin() or (public.vendor_has_platform_access(vendor_id) and exists(select 1 from public.vendors v where v.id=vendor_id and v.owner_user_id=auth.uid()))) with check (public.is_admin() or (public.vendor_has_platform_access(vendor_id) and exists(select 1 from public.vendors v where v.id=vendor_id and v.owner_user_id=auth.uid())));

-- Customers retain access to their orders; expired vendors cannot query commerce records.
drop policy if exists orders_customer_read on public.orders;
drop policy if exists orders_vendor_update on public.orders;
create policy orders_participant_read on public.orders for select using (customer_id=auth.uid() or public.is_admin() or (public.vendor_has_platform_access(vendor_id) and exists(select 1 from public.vendors v where v.id=vendor_id and v.owner_user_id=auth.uid())));

drop policy if exists items_order_read on public.order_items;
create policy items_order_read on public.order_items for select using (exists(select 1 from public.orders o join public.vendors v on v.id=o.vendor_id where o.id=order_id and (o.customer_id=auth.uid() or public.is_admin() or (v.owner_user_id=auth.uid() and public.vendor_has_platform_access(v.id)))));

drop policy if exists reviews_public_read on public.reviews;
drop policy if exists reviews_owner_moderate on public.reviews;
create policy reviews_access_read on public.reviews for select using (public.is_admin() or customer_id=auth.uid() or (public.vendor_has_platform_access(vendor_id) and exists(select 1 from public.vendors v where v.id=vendor_id and ((is_published and v.published) or v.owner_user_id=auth.uid()))));
create policy reviews_owner_moderate on public.reviews for update using (customer_id=auth.uid() or public.is_admin() or (public.vendor_has_platform_access(vendor_id) and exists(select 1 from public.vendors v where v.id=vendor_id and v.owner_user_id=auth.uid())));

drop policy if exists slots_public_read on public.booking_slots;
drop policy if exists slots_owner_manage on public.booking_slots;
create policy slots_access_read on public.booking_slots for select using (public.is_admin() or exists(select 1 from public.products p join public.vendors v on v.id=p.vendor_id where p.id=product_id and public.vendor_has_platform_access(v.id) and ((active and p.is_active and v.published) or v.owner_user_id=auth.uid())));
create policy slots_owner_manage on public.booking_slots for all using (public.is_admin() or exists(select 1 from public.products p join public.vendors v on v.id=p.vendor_id where p.id=product_id and v.owner_user_id=auth.uid() and public.vendor_has_platform_access(v.id))) with check (public.is_admin() or exists(select 1 from public.products p join public.vendors v on v.id=p.vendor_id where p.id=product_id and v.owner_user_id=auth.uid() and public.vendor_has_platform_access(v.id)));

drop policy if exists order_history_participant_read on public.order_status_history;
create policy order_history_participant_read on public.order_status_history for select using (exists(select 1 from public.orders o join public.vendors v on v.id=o.vendor_id where o.id=order_id and (o.customer_id=auth.uid() or public.is_admin() or (v.owner_user_id=auth.uid() and public.vendor_has_platform_access(v.id)))));

commit;
