begin;

create or replace function public.replace_product_variants(target_product_id uuid, variants jsonb)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare item jsonb;
begin
  if jsonb_typeof(variants) <> 'array' then raise exception 'Variants must be a JSON array'; end if;
  if jsonb_array_length(variants) > 100 then raise exception 'A product supports at most 100 variants'; end if;
  if not exists (
    select 1 from public.products p join public.vendors v on v.id=p.vendor_id
    where p.id=target_product_id and (v.owner_user_id=auth.uid() or public.is_admin())
  ) then raise exception 'Product not found or access denied'; end if;

  delete from public.product_variants where product_id=target_product_id;
  for item in select value from jsonb_array_elements(variants)
  loop
    insert into public.product_variants(product_id,variant_name,variant_value,sku,price_modifier,stock_count)
    values(
      target_product_id,
      trim(item->>'variant_name'),
      trim(item->>'variant_value'),
      nullif(trim(item->>'sku'),''),
      coalesce((item->>'price_modifier')::numeric,0),
      coalesce((item->>'stock_count')::integer,0)
    );
  end loop;
end; $$;

grant execute on function public.replace_product_variants(uuid,jsonb) to authenticated;

commit;
