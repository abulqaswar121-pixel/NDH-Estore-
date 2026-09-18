begin;

-- Public commerce records are visible only while their parent storefront is published.
drop policy if exists products_public_read on public.products;
create policy products_public_read on public.products for select using (
  exists (
    select 1 from public.vendors v where v.id=vendor_id and (
      (v.published=true and v.subscription_status in ('trial','active','past_due'))
      or v.owner_user_id=auth.uid() or public.is_admin()
    )
  )
);

drop policy if exists variants_public_read on public.product_variants;
create policy variants_public_read on public.product_variants for select using (
  exists (
    select 1 from public.products p join public.vendors v on v.id=p.vendor_id
    where p.id=product_id and (
      (p.is_active=true and v.published=true and v.subscription_status in ('trial','active','past_due'))
      or v.owner_user_id=auth.uid() or public.is_admin()
    )
  )
);

drop policy if exists zones_public_read on public.shipping_zones;
create policy zones_public_read on public.shipping_zones for select using (
  exists (
    select 1 from public.vendors v where v.id=vendor_id and (
      (active=true and v.published=true and v.subscription_status in ('trial','active','past_due'))
      or v.owner_user_id=auth.uid() or public.is_admin()
    )
  )
);

drop policy if exists cargo_public_read on public.cargo_profiles;
create policy cargo_public_read on public.cargo_profiles for select using (
  exists (
    select 1 from public.vendors v where v.id=vendor_id and (
      (active=true and v.published=true and v.subscription_status in ('trial','active','past_due'))
      or v.owner_user_id=auth.uid() or public.is_admin()
    )
  )
);

drop policy if exists reviews_public_read on public.reviews;
create policy reviews_public_read on public.reviews for select using (
  exists (
    select 1 from public.vendors v where v.id=vendor_id and (
      (is_published=true and v.published=true and v.subscription_status in ('trial','active','past_due'))
      or customer_id=auth.uid() or v.owner_user_id=auth.uid() or public.is_admin()
    )
  )
);

drop policy if exists slots_public_read on public.booking_slots;
create policy slots_public_read on public.booking_slots for select using (
  exists (
    select 1 from public.products p join public.vendors v on v.id=p.vendor_id
    where p.id=product_id and (
      (active=true and p.is_active=true and v.published=true and v.subscription_status in ('trial','active','past_due'))
      or v.owner_user_id=auth.uid() or public.is_admin()
    )
  )
);

commit;
