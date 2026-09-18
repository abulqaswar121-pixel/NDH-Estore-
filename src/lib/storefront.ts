import {createServerFn} from '@tanstack/react-start'
import {queryOptions} from '@tanstack/react-query'
import {getSupabaseServerClient} from './supabase/server'
import {demoVendor,products as demoProducts,variants as demoVariants} from './data'
import type {DesignSettings,Product,ProductVariant,SubscriptionStatus,VendorArchetype} from '@/types/schema'
import type {AssetRef} from './products'

export type StoreProduct=Product&{slug:string;image_urls:AssetRef[];is_active:boolean;volume_cbm:number;allocation_threshold:number|null;variants:ProductVariant[];booking_slots:BookingSlot[]}
export type BookingSlot={id:string;product_id:string;starts_at:string;ends_at:string;capacity:number;reserved_count:number;active:boolean}
export type DeliveryZone={id:string;country_code:string;state:string;zone_name:string;fee:number;estimated_days_min:number|null;estimated_days_max:number|null}
export type CargoProfile={id:string;name:string;origin_country:string;destination_country:string;transport_mode:string;metric:'kg'|'cbm'|'flat';rate:number;currency:string;minimum_charge:number}
export type StoreVendor={id:string;business_name:string;shop_slug:string;whatsapp_number:string;business_category:VendorArchetype;business_description:string;design_settings:DesignSettings;subscription_status:SubscriptionStatus;subscription_tier:string;default_currency:string;timezone:string;seo_title:string|null;seo_description:string|null;meta_pixel_id:string|null}
export type StorefrontData={configured:boolean;notFound:boolean;locked:boolean;vendor:StoreVendor|null;products:StoreProduct[];shippingZones:DeliveryZone[];cargoProfiles:CargoProfile[]}
const configured=()=>Boolean(process.env.VITE_SUPABASE_URL&&process.env.VITE_SUPABASE_ANON_KEY)
const normalizeSlug=(value:string)=>value.toLowerCase().trim().replace(/[^a-z0-9-]/g,'').slice(0,64)
function demo(slug:string):StorefrontData{return {configured:false,notFound:false,locked:false,vendor:{...demoVendor,shop_slug:slug,business_description:'Premium hair, thoughtfully sourced and beautifully finished in Lagos.',default_currency:'NGN',timezone:'Africa/Lagos',seo_title:null,seo_description:null,meta_pixel_id:null},products:demoProducts.map(product=>({...product,slug:product.name.toLowerCase().replace(/[^a-z0-9]+/g,'-'),image_urls:[{url:product.image_url,path:'demo'}],is_active:true,volume_cbm:0,allocation_threshold:null,variants:demoVariants.filter(variant=>variant.product_id===product.id),booking_slots:[]})),shippingZones:[{id:'zone-1',country_code:'NG',state:'Lagos',zone_name:'Lagos Central',fee:2500,estimated_days_min:1,estimated_days_max:2},{id:'zone-2',country_code:'NG',state:'Lagos',zone_name:'Lagos Island',fee:3500,estimated_days_min:1,estimated_days_max:3},{id:'zone-3',country_code:'NG',state:'Lagos',zone_name:'Lagos Outskirts',fee:5000,estimated_days_min:2,estimated_days_max:4}],cargoProfiles:[]}}
export const getPublicStorefront=createServerFn({method:'GET'}).validator((slug:string)=>slug).handler(async({data})=>{
  const slug=normalizeSlug(data);if(!configured())return demo(slug)
  const client=getSupabaseServerClient()
  const {data:vendor,error:vendorError}=await client.from('vendors').select('id,business_name,shop_slug,whatsapp_number,business_category,business_description,design_settings,subscription_status,subscription_tier,default_currency,timezone,seo_title,seo_description,meta_pixel_id').eq('shop_slug',slug).eq('published',true).maybeSingle()
  if(vendorError)throw new Error('Unable to load this storefront.')
  if(!vendor)return {configured:true,notFound:true,locked:false,vendor:null,products:[],shippingZones:[],cargoProfiles:[]} satisfies StorefrontData
  const {data:effectiveStatus}=await client.rpc('effective_subscription_status',{target_vendor_id:vendor.id})
  const resolvedStatus=(effectiveStatus??vendor.subscription_status) as SubscriptionStatus
  const locked=resolvedStatus==='expired'
  const [productResult,zoneResult,cargoResult]=await Promise.all([
    client.from('products').select('id,vendor_id,name,slug,description,base_price,image_url,image_urls,category,is_featured,is_active,stock_count,product_type,weight_kg,volume_cbm,allocation_threshold').eq('vendor_id',vendor.id).eq('is_active',true).order('is_featured',{ascending:false}).order('created_at',{ascending:false}),
    client.from('shipping_zones').select('id,country_code,state,zone_name,fee,estimated_days_min,estimated_days_max').eq('vendor_id',vendor.id).eq('active',true).order('state').order('fee'),
    client.from('cargo_profiles').select('id,name,origin_country,destination_country,transport_mode,metric,rate,currency,minimum_charge').eq('vendor_id',vendor.id).eq('active',true)
  ])
  if(productResult.error||zoneResult.error||cargoResult.error)throw new Error('Unable to load storefront inventory and delivery options.')
  const productRows=productResult.data??[],ids=productRows.map(product=>product.id)
  const [variantResult,slotResult]=ids.length?await Promise.all([
    client.from('product_variants').select('id,product_id,variant_name,variant_value,price_modifier,stock_count').in('product_id',ids),
    client.from('booking_slots').select('id,product_id,starts_at,ends_at,capacity,reserved_count,active').in('product_id',ids).eq('active',true)
  ]):[{data:[],error:null},{data:[],error:null}]
  if(variantResult.error||slotResult.error)throw new Error('Unable to load product options.')
  const products=productRows.map(row=>({...row,image_urls:(Array.isArray(row.image_urls)?row.image_urls:[] as unknown[]) as unknown as AssetRef[],variants:(variantResult.data??[]).filter(variant=>variant.product_id===row.id),booking_slots:(slotResult.data??[]).filter(slot=>slot.product_id===row.id)})) as unknown as StoreProduct[]
  return {configured:true,notFound:false,locked,vendor:{...vendor,subscription_status:resolvedStatus,design_settings:vendor.design_settings as unknown as DesignSettings},products,shippingZones:(zoneResult.data??[]) as DeliveryZone[],cargoProfiles:(cargoResult.data??[]) as CargoProfile[]} satisfies StorefrontData
})
export const storefrontQuery=(slug:string)=>queryOptions({queryKey:['storefront',slug],queryFn:()=>getPublicStorefront({data:slug}),staleTime:60_000})
