import {createServerFn} from '@tanstack/react-start'
import {getSupabaseServerClient} from './supabase/server'
import {dispatchOrderEmails} from './email'

export type CheckoutInput={vendorSlug:string;checkoutToken:string;customer:{name:string;email:string;phone:string;note:string};destination:{country_code:string;state?:string;zone?:string;address?:string};zoneId:string|null;provider:'paystack'|'flutterwave'|'stripe'|'bank_transfer'|'whatsapp';items:Array<{product_id:string;variant_id:string|null;quantity:number}>}
export type OrderSummary={order_id:string;order_number:number;currency:string;subtotal:number;shipping_fee:number;platform_fee:number;total:number}
const configured=()=>Boolean(process.env.VITE_SUPABASE_URL&&process.env.VITE_SUPABASE_ANON_KEY)
export const createOrder=createServerFn({method:'POST'}).validator((value:CheckoutInput)=>value).handler(async({data})=>{
  if(!configured())return {ok:true,error:null,order:{order_id:`demo-${Date.now()}`,order_number:Number(String(Date.now()).slice(-6)),currency:data.destination.country_code==='NG'?'NGN':'USD',subtotal:0,shipping_fee:0,platform_fee:0,total:0} as OrderSummary}
  if(!/^[0-9a-f-]{36}$/i.test(data.checkoutToken))return {ok:false,error:'Invalid checkout session.',order:null}
  if(data.items.length<1||data.items.length>50)return {ok:false,error:'Your cart must contain between one and fifty items.',order:null}
  const client=getSupabaseServerClient()
  const {data:result,error}=await client.rpc('create_storefront_order',{requested_vendor_slug:data.vendorSlug,requested_checkout_token:data.checkoutToken,customer:data.customer,destination:data.destination,requested_zone_id:data.zoneId,requested_provider:data.provider,requested_items:data.items})
  if(error){const message=error.message.toLowerCase();if(message.includes('stock'))return {ok:false,error:'An item no longer has enough stock. Refresh the store and adjust your cart.',order:null};if(message.includes('route')||message.includes('zone'))return {ok:false,error:'The selected delivery option is no longer available.',order:null};return {ok:false,error:'We could not create your order. Check your details and try again.',order:null}}
  const order=result as unknown as OrderSummary
  await dispatchOrderEmails(order.order_id)
  return {ok:true,error:null,order}
})
