begin;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values(
  ('vendor-assets','vendor-assets',true,20971520,array['image/jpeg','image/png','image/webp','image/gif']),
  ('digital-products','digital-products',false,104857600,null)
)
on conflict(id) do update set file_size_limit=excluded.file_size_limit, allowed_mime_types=excluded.allowed_mime_types;

create policy vendor_assets_public_read on storage.objects for select using (bucket_id='vendor-assets');
create policy vendor_assets_owner_insert on storage.objects for insert to authenticated with check (bucket_id='vendor-assets' and (storage.foldername(name))[1]=auth.uid()::text);
create policy vendor_assets_owner_update on storage.objects for update to authenticated using (bucket_id='vendor-assets' and ((storage.foldername(name))[1]=auth.uid()::text or public.is_admin())) with check (bucket_id='vendor-assets' and ((storage.foldername(name))[1]=auth.uid()::text or public.is_admin()));
create policy vendor_assets_owner_delete on storage.objects for delete to authenticated using (bucket_id='vendor-assets' and ((storage.foldername(name))[1]=auth.uid()::text or public.is_admin()));

create policy digital_products_owner_read on storage.objects for select to authenticated using (bucket_id='digital-products' and ((storage.foldername(name))[1]=auth.uid()::text or public.is_admin()));
create policy digital_products_owner_insert on storage.objects for insert to authenticated with check (bucket_id='digital-products' and (storage.foldername(name))[1]=auth.uid()::text);
create policy digital_products_owner_update on storage.objects for update to authenticated using (bucket_id='digital-products' and ((storage.foldername(name))[1]=auth.uid()::text or public.is_admin())) with check (bucket_id='digital-products' and ((storage.foldername(name))[1]=auth.uid()::text or public.is_admin()));
create policy digital_products_owner_delete on storage.objects for delete to authenticated using (bucket_id='digital-products' and ((storage.foldername(name))[1]=auth.uid()::text or public.is_admin()));

commit;
