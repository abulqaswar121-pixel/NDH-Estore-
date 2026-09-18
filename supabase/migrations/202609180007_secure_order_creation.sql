begin;

alter table public.orders add column checkout_token uuid not null default gen_random_uuid() unique;

create table public.exchange_rates (
  currency char(3) primary key,
  ngn_per_unit numeric(18,6) not null check(ngn_per_unit > 0),
  updated_at timestamptz not null default now()
);
insert into public.exchange_rates(currency,ngn_per_unit) values('NGN',1),('USD',1600),('GBP',2100)
on conflict(currency) do nothing;

revoke insert on public.orders from anon,authenticated;
revoke insert on public.order_items from anon,authenticated;

drop policy if exists orders_authenticated_insert on public.orders;
drop policy if exists items_order_insert on public.order_items;

create or replace function public.create_storefront_order(
  requested_vendor_slug text,
  requested_checkout_token uuid,
  customer jsonb,
  destination jsonb,
  requested_zone_id uuid,
  requested_provider public.payment_provider,
  requested_items jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  selected_vendor public.vendors%rowtype;
  selected_product public.products%rowtype;
  selected_variant public.product_variants%rowtype;
  selected_zone public.shipping_zones%rowtype;
  selected_cargo public.cargo_profiles%rowtype;
  item jsonb;
  created_order_id uuid;
  created_order_number bigint;
  quantity integer;
  item_unit_ngn numeric(14,2);
  subtotal_ngn numeric(14,2):=0;
  shipping_ngn numeric(14,2):=0;
  total_weight numeric(14,3):=0;
  total_volume numeric(14,4):=0;
  physical_items integer:=0;
  output_currency char(3);
  exchange_rate numeric(18,6):=1;
  destination_country char(2);
  computed_subtotal numeric(14,2);
  computed_shipping numeric(14,2);
  computed_total numeric(14,2);
  computed_platform_fee numeric(14,2);
  normalized_email text;
begin
  if requested_checkout_token is null then raise exception 'Checkout token is required'; end if;
  if exists(select 1 from public.orders where checkout_token=requested_checkout_token) then
    return (select jsonb_build_object('order_id',id,'order_number',order_number,'currency',currency,'subtotal',subtotal,'shipping_fee',shipping_fee,'platform_fee',platform_fee,'total',total) from public.orders where checkout_token=requested_checkout_token);
  end if;
  select * into selected_vendor from public.vendors
  where shop_slug=lower(trim(requested_vendor_slug)) and published=true
    and subscription_status in ('trial','active','past_due');
  if not found then raise exception 'Store is unavailable'; end if;
  if jsonb_typeof(requested_items)<>'array' or jsonb_array_length(requested_items)=0 or jsonb_array_length(requested_items)>50 then raise exception 'Order must contain between one and fifty items'; end if;
  normalized_email=lower(trim(customer->>'email'));
  if normalized_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then raise exception 'Valid customer email required'; end if;
  if char_length(trim(customer->>'name'))<2 then raise exception 'Customer name required'; end if;
  destination_country=upper(coalesce(destination->>'country_code','NG'));
  if destination_country<>'NG' and requested_provider in ('whatsapp','bank_transfer','paystack') then raise exception 'International orders require a global card provider'; end if;
  if destination_country='NG' and requested_provider in ('stripe') then raise exception 'Unsupported local payment provider'; end if;
  if requested_provider='whatsapp' and char_length(regexp_replace(coalesce(customer->>'phone',''),'[^0-9]','','g'))<10 then raise exception 'A phone number is required for WhatsApp checkout'; end if;
  output_currency=case when destination_country='NG' then 'NGN' else 'USD' end;
  select ngn_per_unit into exchange_rate from public.exchange_rates where currency=output_currency;
  if exchange_rate is null then raise exception 'Checkout currency unavailable'; end if;

  for item in select value from jsonb_array_elements(requested_items)
  loop
    selected_variant.id=null;selected_variant.variant_value=null;selected_variant.price_modifier=0;
    quantity=coalesce((item->>'quantity')::integer,0);
    if quantity<1 or quantity>100 then raise exception 'Invalid item quantity'; end if;
    select * into selected_product from public.products where id=(item->>'product_id')::uuid and vendor_id=selected_vendor.id and is_active=true for share;
    if not found then raise exception 'A selected product is unavailable'; end if;
    item_unit_ngn=selected_product.base_price;
    if nullif(item->>'variant_id','') is not null then
      select * into selected_variant from public.product_variants where id=(item->>'variant_id')::uuid and product_id=selected_product.id for share;
      if not found then raise exception 'A selected product option is unavailable'; end if;
      if selected_variant.stock_count<quantity then raise exception 'Insufficient variant stock'; end if;
      item_unit_ngn=item_unit_ngn+selected_variant.price_modifier;
    elsif selected_product.product_type='physical' and selected_product.stock_count<quantity then raise exception 'Insufficient product stock';
    end if;
    if selected_product.product_type='physical' then
      if selected_variant.id is not null then
        update public.product_variants set stock_count=stock_count-quantity where id=selected_variant.id;
      else
        update public.products set stock_count=stock_count-quantity where id=selected_product.id;
      end if;
    end if;
    subtotal_ngn=subtotal_ngn+(item_unit_ngn*quantity);
    if selected_product.product_type='physical' then physical_items=physical_items+quantity;total_weight=total_weight+(selected_product.weight_kg*quantity);total_volume=total_volume+(selected_product.volume_cbm*quantity);end if;
  end loop;

  if physical_items>0 then
    if selected_vendor.business_category='cargo_logistics' then
      select * into selected_cargo from public.cargo_profiles where vendor_id=selected_vendor.id and active=true and destination_country=destination_country order by created_at limit 1;
      if not found then raise exception 'No cargo route is available for this destination'; end if;
      shipping_ngn=case selected_cargo.metric when 'kg' then total_weight*selected_cargo.rate when 'cbm' then total_volume*selected_cargo.rate else selected_cargo.rate end;
      if selected_cargo.currency<>'NGN' then shipping_ngn=shipping_ngn*(select ngn_per_unit from public.exchange_rates where currency=selected_cargo.currency);end if;
      shipping_ngn=greatest(shipping_ngn,selected_cargo.minimum_charge);
    elsif destination_country='NG' then
      if requested_zone_id is null then raise exception 'Delivery zone required'; end if;
      select * into selected_zone from public.shipping_zones where id=requested_zone_id and vendor_id=selected_vendor.id and active=true;
      if not found then raise exception 'Delivery zone is unavailable'; end if;
      shipping_ngn=selected_zone.fee;
    else
      shipping_ngn=35*(select ngn_per_unit from public.exchange_rates where currency='USD');
    end if;
  end if;

  if physical_items>0 and char_length(trim(coalesce(destination->>'address','')))<8 then raise exception 'A complete delivery address is required'; end if;
  computed_subtotal=round(subtotal_ngn/exchange_rate,2);
  computed_shipping=round(shipping_ngn/exchange_rate,2);
  computed_total=computed_subtotal+computed_shipping;
  computed_platform_fee=round(computed_subtotal*selected_vendor.platform_fee_percentage/100,2);

  insert into public.orders(checkout_token,vendor_id,customer_id,customer_email,customer_name,customer_phone,status,payment_provider,currency,subtotal,shipping_fee,platform_fee,total,shipping_address,delivery_zone_id,customer_note)
  values(requested_checkout_token,selected_vendor.id,auth.uid(),normalized_email,trim(customer->>'name'),nullif(trim(customer->>'phone'),''),case when requested_provider in ('whatsapp','bank_transfer') then 'pending' else 'awaiting_payment' end,requested_provider,output_currency,computed_subtotal,computed_shipping,computed_platform_fee,computed_total,destination,selected_zone.id,nullif(trim(customer->>'note'),''))
  on conflict(checkout_token) do update set checkout_token=excluded.checkout_token
  returning id,order_number into created_order_id,created_order_number;

  if not exists(select 1 from public.order_items where order_id=created_order_id) then
    for item in select value from jsonb_array_elements(requested_items)
    loop
      quantity=(item->>'quantity')::integer;
      select * into selected_product from public.products where id=(item->>'product_id')::uuid;
      selected_variant.id=null;selected_variant.variant_value=null;selected_variant.price_modifier=0;
      if nullif(item->>'variant_id','') is not null then select * into selected_variant from public.product_variants where id=(item->>'variant_id')::uuid;end if;
      item_unit_ngn=selected_product.base_price+coalesce(selected_variant.price_modifier,0);
      insert into public.order_items(order_id,product_id,variant_id,product_name,variant_description,quantity,unit_price,weight_kg)
      values(created_order_id,selected_product.id,selected_variant.id,selected_product.name,selected_variant.variant_value,quantity,round(item_unit_ngn/exchange_rate,2),selected_product.weight_kg);
    end loop;
  end if;

  return jsonb_build_object('order_id',created_order_id,'order_number',created_order_number,'currency',output_currency,'subtotal',computed_subtotal,'shipping_fee',computed_shipping,'platform_fee',computed_platform_fee,'total',computed_total);
end $$;

grant execute on function public.create_storefront_order(text,uuid,jsonb,jsonb,uuid,public.payment_provider,jsonb) to anon,authenticated;
revoke all on public.exchange_rates from anon,authenticated;
grant select on public.exchange_rates to anon,authenticated;

commit;
