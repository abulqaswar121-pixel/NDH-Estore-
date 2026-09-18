begin;

revoke select on public.vendors from anon;
grant select (
  id,business_name,shop_slug,whatsapp_number,business_category,business_description,
  design_settings,subscription_tier,subscription_status,default_currency,timezone,
  seo_title,seo_description,published,created_at,updated_at
) on public.vendors to anon;

revoke select on public.products from anon;
grant select (
  id,vendor_id,name,slug,description,base_price,compare_at_price,image_url,image_urls,
  category,is_featured,is_active,stock_count,product_type,weight_kg,volume_cbm,
  allocation_threshold,metadata,created_at,updated_at
) on public.products to anon;

revoke all on public.user_roles from anon;
revoke all on public.users from anon;
revoke all on public.payouts from anon;
revoke all on public.subscription_events from anon;

commit;
