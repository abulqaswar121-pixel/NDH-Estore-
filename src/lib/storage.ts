import {createServerFn} from '@tanstack/react-start'
import {getCookie} from '@tanstack/react-start/server'
import {getSupabaseServerClient} from './supabase/server'

const ACCESS_COOKIE='ndh_access_token'
const imageTypes=new Set(['image/jpeg','image/png','image/webp','image/gif'])
type AssetKind='product'|'branding'
const configured=()=>Boolean(process.env.VITE_SUPABASE_URL&&process.env.VITE_SUPABASE_ANON_KEY)
async function auth(){
  if(!configured())return null
  const token=getCookie(ACCESS_COOKIE);if(!token)throw new Error('Authentication required.')
  const client=getSupabaseServerClient(token);const {data:{user}}=await client.auth.getUser(token);if(!user)throw new Error('Your session has expired.')
  const {data:vendor}=await client.from('vendors').select('id').eq('owner_user_id',user.id).maybeSingle();if(vendor){const {data:hasAccess}=await client.rpc('vendor_has_platform_access',{target_vendor_id:vendor.id});if(!hasAccess)throw new Error('Renew your subscription before uploading new assets.')}
  return {client,user}
}
function safeName(name:string){const pieces=name.toLowerCase().split('.'),extension=(pieces.pop()??'bin').replace(/[^a-z0-9]/g,'');const stem=pieces.join('-').replace(/[^a-z0-9]+/g,'-').replace(/^-|-$/g,'').slice(0,50)||'asset';return `${stem}-${crypto.randomUUID()}.${extension}`}
export const createAssetUpload=createServerFn({method:'POST'}).validator((value:{fileName:string;contentType:string;size:number;kind:AssetKind})=>value).handler(async({data})=>{
  if(!imageTypes.has(data.contentType))return {ok:false,error:'Use a JPEG, PNG, WebP or GIF image.',path:null,signedUrl:null,publicUrl:null}
  if(data.size<=0||data.size>20*1024*1024)return {ok:false,error:'Images must be smaller than 20 MB.',path:null,signedUrl:null,publicUrl:null}
  const context=await auth();if(!context){const demoUrl=data.kind==='branding'?'/ndh-logo.png':'/hero-fashion-real.jpg';return {ok:true,error:null,path:`demo/${data.fileName}`,signedUrl:'demo',publicUrl:demoUrl}}
  const folder=data.kind==='branding'?'branding':'products',path=`${context.user.id}/${folder}/${safeName(data.fileName)}`
  const {data:upload,error}=await context.client.storage.from('vendor-assets').createSignedUploadUrl(path)
  if(error)return {ok:false,error:'Unable to prepare this upload.',path:null,signedUrl:null,publicUrl:null}
  const {data:publicData}=context.client.storage.from('vendor-assets').getPublicUrl(path)
  return {ok:true,error:null,path,signedUrl:upload.signedUrl,publicUrl:publicData.publicUrl}
})
export const removeAsset=createServerFn({method:'POST'}).validator((path:string)=>path).handler(async({data:path})=>{
  const context=await auth();if(!context)return {ok:true,error:null}
  if(!path.startsWith(`${context.user.id}/`))return {ok:false,error:'You cannot remove an asset owned by another account.'}
  const {error}=await context.client.storage.from('vendor-assets').remove([path])
  return error?{ok:false,error:'Unable to remove this image.'}:{ok:true,error:null}
})
