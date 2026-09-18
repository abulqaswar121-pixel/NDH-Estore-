do $$
declare
  seed_user_id uuid;
  seed_vendor_id uuid;
  seed_product_id uuid;
begin
  select id into seed_user_id from public.users order by created_at limit 1;
  if seed_user_id is null then
    raise notice 'Seed skipped: create a local auth user first, then run supabase db reset again.';
    return;
  end if;

  insert into public.user_roles(user_id, role) values(seed_user_id, 'vendor') on conflict do nothing;
  insert into public.vendors(
    owner_user_id,email,business_name,shop_slug,whatsapp_number,business_category,
    business_description,subscription_tier,billing_cycle,subscription_status,published
  ) values(
    seed_user_id,'hello@amari.test','Amari Atelier','amari-atelier','2349029932794','wigs_fashion',
    'Premium hair, thoughtfully sourced and beautifully finished in Lagos.','pro','yearly','active',true
  ) on conflict(shop_slug) do update set owner_user_id=excluded.owner_user_id
  returning id into seed_vendor_id;

  insert into public.products(vendor_id,name,slug,description,base_price,image_url,category,is_featured,stock_count,product_type,weight_kg)
  values(seed_vendor_id,'Raw Vietnamese Wave','raw-vietnamese-wave','Silky double-drawn raw hair, finished by hand.',185000,'https://images.unsplash.com/photo-1529139574466-a303027c1d8b?auto=format&fit=crop&w=900&q=80','Signature wigs',true,12,'physical',0.6)
  on conflict(vendor_id,slug) do update set name=excluded.name
  returning id into seed_product_id;

  insert into public.product_variants(product_id,variant_name,variant_value,price_modifier,stock_count) values
    (seed_product_id,'Length','20 inches',0,4),
    (seed_product_id,'Length','24 inches',35000,5),
    (seed_product_id,'Length','30 inches',85000,3)
  on conflict(product_id,variant_name,variant_value) do nothing;

  insert into public.shipping_zones(vendor_id,state,zone_name,fee,estimated_days_min,estimated_days_max) values
    (seed_vendor_id,'Lagos','Lagos Central',2500,1,2),
    (seed_vendor_id,'Lagos','Lagos Island',3500,1,3),
    (seed_vendor_id,'Lagos','Lagos Outskirts',5000,2,4)
  on conflict(vendor_id,country_code,state,zone_name) do nothing;
end $$;
