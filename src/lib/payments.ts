import {createServerFn} from '@tanstack/react-start'
import {getSupabaseAdminClient} from './supabase/server'
import type {Json} from '@/types/database'
import {dispatchOrderEmails} from './email'
import {sendMetaPurchase} from './meta'

type Provider='paystack'|'flutterwave'
type PaymentOrder={id:string;order_number:number;checkout_token:string;customer_email:string;customer_name:string;customer_phone:string|null;currency:string;total:number;status:string;payment_provider:string|null;payment_reference:string|null;metadata:Record<string,unknown>|null}
const configured=()=>Boolean(process.env.VITE_SUPABASE_URL&&process.env.SUPABASE_SERVICE_ROLE_KEY)
const appUrl=()=>process.env.APP_URL??'http://localhost:5173'
function required(name:string){const value=process.env[name];if(!value)throw new Error(`${name} is not configured.`);return value}
async function orderForCheckout(orderId:string,checkoutToken:string){
  const admin=getSupabaseAdminClient()
  const {data,error}=await admin.from('orders').select('id,order_number,checkout_token,customer_email,customer_name,customer_phone,currency,total,status,payment_provider,payment_reference,metadata').eq('id',orderId).eq('checkout_token',checkoutToken).single()
  if(error||!data)throw new Error('Order not found.')
  return data as unknown as PaymentOrder
}
async function jsonRequest(url:string,init:RequestInit){
  const response=await fetch(url,init)
  const body=await response.json().catch(()=>null) as Record<string,unknown>|null
  if(!response.ok)throw new Error(typeof body?.message==='string'?body.message:'Payment provider request failed.')
  return body??{}
}
export const initializeOrderPayment=createServerFn({method:'POST'})
  .validator((value:{orderId:string;checkoutToken:string;provider:Provider})=>value)
  .handler(async({data})=>{
    if(!configured())return {ok:true,error:null,authorizationUrl:`/payment/callback?demo=1&provider=${data.provider}`,reference:`DEMO-${Date.now()}`}
    if(!/^[0-9a-f-]{36}$/i.test(data.orderId)||!/^[0-9a-f-]{36}$/i.test(data.checkoutToken))return {ok:false,error:'Invalid payment request.',authorizationUrl:null,reference:null}
    try{
      const order=await orderForCheckout(data.orderId,data.checkoutToken)
      if(order.status==='paid')return {ok:false,error:'This order has already been paid.',authorizationUrl:null,reference:null}
      if(order.status!=='awaiting_payment')return {ok:false,error:'This order is not awaiting card payment.',authorizationUrl:null,reference:null}
      if(data.provider==='paystack'&&order.currency!=='NGN')return {ok:false,error:'Paystack is available only for Naira orders.',authorizationUrl:null,reference:null}
      if(data.provider==='flutterwave'&&order.currency==='NGN')return {ok:false,error:'Flutterwave global checkout is reserved for international orders.',authorizationUrl:null,reference:null}
      const previous=(order.metadata?.payment_initialization??null) as {provider?:string;authorization_url?:string;reference?:string}|null
      if(previous?.provider===data.provider&&previous.authorization_url&&previous.reference)return {ok:true,error:null,authorizationUrl:previous.authorization_url,reference:previous.reference}
      const reference=`NDH-${order.order_number}-${data.checkoutToken.slice(0,8)}`
      let authorizationUrl:string
      if(data.provider==='paystack'){
        const response=await jsonRequest('https://api.paystack.co/transaction/initialize',{
          method:'POST',headers:{Authorization:`Bearer ${required('PAYSTACK_SECRET_KEY')}`,'Content-Type':'application/json'},
          body:JSON.stringify({email:order.customer_email,amount:Math.round(order.total*100),currency:'NGN',reference,callback_url:`${appUrl()}/payment/callback?provider=paystack`,metadata:{order_id:order.id,order_number:order.order_number}})
        })
        const providerData=response.data as {authorization_url?:string}|undefined
        if(!providerData?.authorization_url)throw new Error('Paystack did not return a checkout URL.')
        authorizationUrl=providerData.authorization_url
      }else{
        const response=await jsonRequest('https://api.flutterwave.com/v3/payments',{
          method:'POST',headers:{Authorization:`Bearer ${required('FLUTTERWAVE_SECRET_KEY')}`,'Content-Type':'application/json'},
          body:JSON.stringify({tx_ref:reference,amount:order.total,currency:order.currency,redirect_url:`${appUrl()}/payment/callback?provider=flutterwave`,customer:{email:order.customer_email,name:order.customer_name,phonenumber:order.customer_phone??undefined},customizations:{title:'NDH Estore Payment',description:`Order NDH-${order.order_number}`},meta:{order_id:order.id,order_number:order.order_number}})
        })
        const providerData=response.data as {link?:string}|undefined
        if(!providerData?.link)throw new Error('Flutterwave did not return a checkout URL.')
        authorizationUrl=providerData.link
      }
      const admin=getSupabaseAdminClient()
      const metadata={...(order.metadata??{}),payment_initialization:{provider:data.provider,authorization_url:authorizationUrl,reference,initialized_at:new Date().toISOString()}}
      const {error:updateError}=await admin.from('orders').update({payment_provider:data.provider,payment_reference:reference,metadata}).eq('id',order.id)
      if(updateError)throw new Error('Payment initialized, but the order could not be updated.')
      return {ok:true,error:null,authorizationUrl,reference}
    }catch(error){
      return {ok:false,error:error instanceof Error?error.message:'Unable to initialize payment.',authorizationUrl:null,reference:null}
    }
  })

export async function verifyProviderPayment(provider:Provider,reference:string,transactionId?:string){
  const admin=getSupabaseAdminClient()
  const {data:rawOrder}=await admin.from('orders').select('id,currency,total,status,payment_reference').eq('payment_reference',reference).maybeSingle()
  const order=rawOrder as unknown as Pick<PaymentOrder,'id'|'currency'|'total'|'status'|'payment_reference'>|null
  if(!order)throw new Error('Matching order not found.')
  if(order.status==='paid')return {paid:true,orderId:order.id,alreadyProcessed:true}
  let paid=false,amount=0,currency='',payload:Record<string,unknown>={}
  if(provider==='paystack'){
    const result=await jsonRequest(`https://api.paystack.co/transaction/verify/${encodeURIComponent(reference)}`,{headers:{Authorization:`Bearer ${required('PAYSTACK_SECRET_KEY')}`}})
    const data=result.data as Record<string,unknown>|undefined
    paid=data?.status==='success';amount=Number(data?.amount??0)/100;currency=String(data?.currency??'');payload=data??{}
  }else{
    if(!transactionId)throw new Error('Flutterwave transaction ID is required.')
    const result=await jsonRequest(`https://api.flutterwave.com/v3/transactions/${encodeURIComponent(transactionId)}/verify`,{headers:{Authorization:`Bearer ${required('FLUTTERWAVE_SECRET_KEY')}`}})
    const data=result.data as Record<string,unknown>|undefined
    paid=data?.status==='successful'&&data?.tx_ref===reference;amount=Number(data?.amount??0);currency=String(data?.currency??'');payload=data??{}
  }
  if(!paid||currency!==order.currency||Math.abs(amount-order.total)>.01)throw new Error('Payment verification did not match this order.')
  const {error}=await admin.rpc('mark_order_paid',{target_order_id:order.id,provider_reference:reference,paid_payload:payload as Json})
  if(error)throw new Error('Unable to mark this order as paid.')
  await dispatchOrderEmails(order.id)
  await sendMetaPurchase(order.id).catch(()=>undefined)
  return {paid:true,orderId:order.id,alreadyProcessed:false}
}
export const verifyPaymentReturn=createServerFn({method:'POST'})
  .validator((value:{provider:Provider;reference:string;transactionId?:string})=>value)
  .handler(async({data})=>{
    if(!configured())return {ok:true,error:null,orderId:'demo-order'}
    try{const verified=await verifyProviderPayment(data.provider,data.reference,data.transactionId);return {ok:verified.paid,error:null,orderId:verified.orderId}}
    catch(error){return {ok:false,error:error instanceof Error?error.message:'Payment could not be verified.',orderId:null}}
  })
