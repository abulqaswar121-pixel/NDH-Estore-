import {createServerFn} from '@tanstack/react-start'
import {getCookie} from '@tanstack/react-start/server'
import {queryOptions} from '@tanstack/react-query'
import {getSupabaseServerClient} from './supabase/server'
import {products as demoProducts,variants as demoVariants} from './data'
import type {Product,ProductVariant} from '@/types/schema'

const ACCESS_COOKIE='ndh_access_token'
const configured=()=>Boolean(process.env.VITE_SUPABASE_URL&&process.env.VITE_SUPABASE_ANON_KEY)
const slugify=(value:string)=>value.toLowerCase().trim().replace(/[^a-z0-9]+/g,'-').replace(/^-+|-+$/g,'').slice(0,80)
export type AssetRef={url:string;path:string}
export type VariantInput={id?:string;variantName:string;variantValue:string;priceModifier:number;stockCount:number;sku?:string}
export type ProductInput={id?:string;name:string;description:string;basePrice:number;imageUrl:string;imageUrls:AssetRef[];category:string;isFeatured:boolean;isActive:boolean;stockCount:number;productType:'physical'|'booking'|'service'|'digital';weightKg:number;volumeCbm:number;allocationThreshold:number|null;variants:VariantInput[]}
export type VendorProduct=Product&{slug:string;image_urls:AssetRef[];is_active:boolean;volume_cbm:number;allocation_threshold:number|null;variants:ProductVariant[]}

async function context(){
  if(!configured())return null
  const token=getCookie(ACCESS_COOKIE);if(!token)throw new Error('Authentication required.')
  const client=getSupabaseServerClient(token);const {data:{user}}=await client.auth.getUser(token);if(!user)throw new Error('Your session has expired.')
  const {data:vendor}=await client.from('vendors').select('id,subscription_tier,business_category').eq('owner_user_id',user.id).single()
  if(!vendor)throw new Error('Complete store onboarding before managing products.')
  const {data:hasAccess}=await client.rpc('vendor_has_platform_access',{target_vendor_id:vendor.id});if(!hasAccess)throw new Error('Your subscription has expired. Renew from Billing to manage products.')
  return {client,user,vendor}
}
function validate(input:ProductInput){
  if(input.name.trim().length<2||input.name.trim().length>180)return 'Product name must contain between 2 and 180 characters.'
  if(!Number.isFinite(input.basePrice)||input.basePrice<0)return 'Enter a valid product price.'
  if(!Number.isInteger(input.stockCount)||input.stockCount<0)return 'Stock cannot be negative.'
  if(input.weightKg<0||input.volumeCbm<0)return 'Weight and volume cannot be negative.'
  if(input.variants.length>100)return 'A product can have at most 100 variants.'
  if(input.variants.some(v=>!v.variantName.trim()||!v.variantValue.trim()||v.stockCount<0||!Number.isFinite(v.priceModifier)))return 'Complete every variant and use valid price and stock values.'
  const unique=new Set(input.variants.map(v=>`${v.variantName.trim().toLowerCase()}::${v.variantValue.trim().toLowerCase()}`));if(unique.size!==input.variants.length)return 'Each variant name and value combination must be unique.'
  return null
}

export const getVendorProducts=createServerFn({method:'GET'}).handler(async():Promise<{configured:boolean;businessCategory:import('@/types/schema').VendorArchetype;products:VendorProduct[]} >=>{
  const auth=await context();if(!auth)return {configured:false,businessCategory:'wigs_fashion',products:demoProducts.map(product=>({...product,slug:slugify(product.name),image_urls:[{url:product.image_url,path:'demo/product'}],is_active:true,volume_cbm:0,allocation_threshold:null,variants:demoVariants.filter(variant=>variant.product_id===product.id)}))}
  const {data,error}=await auth.client.from('products').select('id,vendor_id,name,slug,description,base_price,image_url,image_urls,category,is_featured,is_active,stock_count,product_type,weight_kg,volume_cbm,allocation_threshold').eq('vendor_id',auth.vendor.id).order('created_at',{ascending:false})
  if(error)throw new Error('Unable to load inventory.')
  const ids=(data??[]).map(row=>row.id)
  const variantResult=ids.length?await auth.client.from('product_variants').select('id,product_id,variant_name,variant_value,price_modifier,stock_count').in('product_id',ids):{data:[] as ProductVariant[],error:null}
  if(variantResult.error)throw new Error('Unable to load product variants.')
  return {configured:true,businessCategory:auth.vendor.business_category,products:(data??[]).map(row=>({...row,variants:(variantResult.data??[]).filter(variant=>variant.product_id===row.id)})) as unknown as VendorProduct[]}
})

export const createVendorProduct=createServerFn({method:'POST'}).validator((value:ProductInput)=>value).handler(async({data})=>{
  const errorMessage=validate(data);if(errorMessage)return {ok:false,error:errorMessage,productId:null}
  const auth=await context();if(!auth)return {ok:true,error:null,productId:`demo-${Date.now()}`}
  if(auth.vendor.subscription_tier==='starter'&&data.productType==='booking')return {ok:false,error:'Booking products require the Pro plan or higher.',productId:null}
  const {count}=await auth.client.from('products').select('id',{count:'exact',head:true}).eq('vendor_id',auth.vendor.id)
  if(auth.vendor.subscription_tier==='starter'&&(count??0)>=30)return {ok:false,error:'The Starter plan supports a maximum of 30 products. Upgrade to add more.',productId:null}
  const baseSlug=slugify(data.name);let slug=baseSlug
  const {data:collision}=await auth.client.from('products').select('id').eq('vendor_id',auth.vendor.id).eq('slug',slug).maybeSingle();if(collision)slug=`${baseSlug}-${Date.now().toString().slice(-6)}`
  const {data:product,error}=await auth.client.from('products').insert({vendor_id:auth.vendor.id,name:data.name.trim(),slug,description:data.description.trim(),base_price:data.basePrice,image_url:data.imageUrl.trim(),image_urls:data.imageUrls,category:data.category.trim()||'General',is_featured:data.isFeatured,is_active:data.isActive,stock_count:data.stockCount,product_type:data.productType,weight_kg:data.weightKg,volume_cbm:data.volumeCbm,allocation_threshold:data.allocationThreshold}).select('id').single()
  if(error||!product)return {ok:false,error:'Unable to create this product.',productId:null}
  if(data.variants.length){const {error:variantError}=await auth.client.from('product_variants').insert(data.variants.map(variant=>({product_id:product.id,variant_name:variant.variantName.trim(),variant_value:variant.variantValue.trim(),price_modifier:variant.priceModifier,stock_count:variant.stockCount,sku:variant.sku?.trim()||null})));if(variantError){await auth.client.from('products').delete().eq('id',product.id);return {ok:false,error:'The product variants could not be saved.',productId:null}}}
  return {ok:true,error:null,productId:product.id}
})

export const updateVendorProduct=createServerFn({method:'POST'}).validator((value:ProductInput&{id:string})=>value).handler(async({data})=>{
  const errorMessage=validate(data);if(errorMessage)return {ok:false,error:errorMessage}
  const auth=await context();if(!auth)return {ok:true,error:null}
  if(auth.vendor.subscription_tier==='starter'&&data.productType==='booking')return {ok:false,error:'Booking products require the Pro plan or higher.'}
  const {data:owned}=await auth.client.from('products').select('id').eq('id',data.id).eq('vendor_id',auth.vendor.id).maybeSingle();if(!owned)return {ok:false,error:'Product not found.'}
  const {error}=await auth.client.from('products').update({name:data.name.trim(),description:data.description.trim(),base_price:data.basePrice,image_url:data.imageUrl.trim(),image_urls:data.imageUrls,category:data.category.trim()||'General',is_featured:data.isFeatured,is_active:data.isActive,stock_count:data.stockCount,product_type:data.productType,weight_kg:data.weightKg,volume_cbm:data.volumeCbm,allocation_threshold:data.allocationThreshold}).eq('id',data.id)
  if(error)return {ok:false,error:'Unable to update this product.'}
  const {error:variantError}=await auth.client.rpc('replace_product_variants',{target_product_id:data.id,variants:data.variants.map(variant=>({variant_name:variant.variantName.trim(),variant_value:variant.variantValue.trim(),price_modifier:variant.priceModifier,stock_count:variant.stockCount,sku:variant.sku?.trim()||null}))})
  if(variantError)return {ok:false,error:'Product updated, but its variants could not be replaced.'}
  return {ok:true,error:null}
})

export const deleteVendorProduct=createServerFn({method:'POST'}).validator((id:string)=>id).handler(async({data:id})=>{
  const auth=await context();if(!auth)return {ok:true,error:null}
  const {data:product}=await auth.client.from('products').select('image_urls').eq('id',id).eq('vendor_id',auth.vendor.id).maybeSingle()
  const {error}=await auth.client.from('products').delete().eq('id',id).eq('vendor_id',auth.vendor.id)
  if(error)return {ok:false,error:'Unable to delete this product.'}
  const images=(Array.isArray(product?.image_urls)?product.image_urls:[]) as unknown as AssetRef[]
  const ownedPaths=images.map(image=>image?.path).filter((path):path is string=>Boolean(path&&path.startsWith(`${auth.user.id}/`)))
  if(ownedPaths.length)await auth.client.storage.from('vendor-assets').remove(ownedPaths)
  return {ok:true,error:null}
})

export const vendorProductsQuery=()=>queryOptions({queryKey:['dashboard','products'],queryFn:()=>getVendorProducts(),staleTime:15_000})
