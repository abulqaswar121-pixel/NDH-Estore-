import {createServerFn} from '@tanstack/react-start'
import {deleteCookie,getCookie,setCookie} from '@tanstack/react-start/server'
import {getSupabaseServerClient} from './supabase/server'
import type {UserRole} from '@/types/schema'

const ACCESS_COOKIE='ndh_access_token'
const REFRESH_COOKIE='ndh_refresh_token'
const cookieOptions={httpOnly:true,secure:process.env.NODE_ENV==='production',sameSite:'lax' as const,path:'/'}
export type AuthUser={id:string;email:string;fullName:string;roles:UserRole[]}
export type AuthState={configured:boolean;user:AuthUser|null}

function configured(){return Boolean(process.env.VITE_SUPABASE_URL&&process.env.VITE_SUPABASE_ANON_KEY)}
function saveSession(session:{access_token:string;refresh_token:string;expires_in:number}){
  setCookie(ACCESS_COOKIE,session.access_token,{...cookieOptions,maxAge:session.expires_in})
  setCookie(REFRESH_COOKIE,session.refresh_token,{...cookieOptions,maxAge:60*60*24*30})
}
function clearSession(){deleteCookie(ACCESS_COOKIE,cookieOptions);deleteCookie(REFRESH_COOKIE,cookieOptions)}
function cleanAuthError(error:unknown){const message=error instanceof Error?error.message:'Authentication failed';if(message.toLowerCase().includes('invalid login'))return 'The email or password is incorrect.';if(message.toLowerCase().includes('already registered'))return 'An account already exists for this email.';return message}
async function resolveUser():Promise<AuthState>{
  if(!configured())return {configured:false,user:null}
  let token=getCookie(ACCESS_COOKIE)
  let client=getSupabaseServerClient(token)
  let {data:{user}}=await client.auth.getUser(token)
  if(!user){
    const refreshToken=getCookie(REFRESH_COOKIE)
    if(refreshToken){
      const refreshed=await client.auth.refreshSession({refresh_token:refreshToken})
      if(refreshed.data.session){saveSession(refreshed.data.session);token=refreshed.data.session.access_token;client=getSupabaseServerClient(token);user=refreshed.data.user}
    }
  }
  if(!user){clearSession();return {configured:true,user:null}}
  const [profileResult,rolesResult]=await Promise.all([
    client.from('users').select('full_name').eq('id',user.id).single(),
    client.from('user_roles').select('role').eq('user_id',user.id)
  ])
  const profile=profileResult.data as unknown as {full_name:string}|null
  const roleRows=rolesResult.data as unknown as Array<{role:UserRole}>|null
  return {configured:true,user:{id:user.id,email:user.email??'',fullName:profile?.full_name??user.user_metadata.full_name??'',roles:(roleRows??[]).map(row=>row.role)}}
}

export const getAuthState=createServerFn({method:'GET'}).handler(resolveUser)

export const signIn=createServerFn({method:'POST'}).validator((value:{email:string;password:string})=>value).handler(async({data})=>{
  if(!configured())return {ok:false,error:'Supabase has not been configured for this environment.'}
  if(!/^\S+@\S+\.\S+$/.test(data.email)||data.password.length<8)return {ok:false,error:'Enter a valid email and a password of at least eight characters.'}
  const client=getSupabaseServerClient()
  const {data:result,error}=await client.auth.signInWithPassword({email:data.email.trim().toLowerCase(),password:data.password})
  if(error||!result.session)return {ok:false,error:cleanAuthError(error)}
  saveSession(result.session)
  return {ok:true,error:null}
})

export const signUp=createServerFn({method:'POST'}).validator((value:{email:string;password:string;fullName:string;role:'vendor'|'customer'})=>value).handler(async({data})=>{
  if(!configured())return {ok:false,error:'Supabase has not been configured for this environment.',requiresEmailConfirmation:false}
  if(data.fullName.trim().length<2)return {ok:false,error:'Enter your full name.',requiresEmailConfirmation:false}
  if(!/^\S+@\S+\.\S+$/.test(data.email)||data.password.length<8)return {ok:false,error:'Enter a valid email and a password of at least eight characters.',requiresEmailConfirmation:false}
  const client=getSupabaseServerClient()
  const {data:result,error}=await client.auth.signUp({email:data.email.trim().toLowerCase(),password:data.password,options:{emailRedirectTo:`${process.env.APP_URL??'http://localhost:5173'}/signin`,data:{full_name:data.fullName.trim(),requested_role:data.role}}})
  if(error)return {ok:false,error:cleanAuthError(error),requiresEmailConfirmation:false}
  if(result.session)saveSession(result.session)
  return {ok:true,error:null,requiresEmailConfirmation:!result.session}
})

export const acceptAuthTokens=createServerFn({method:'POST'}).validator((value:{accessToken:string;refreshToken:string})=>value).handler(async({data})=>{
  if(!configured())return {ok:false,error:'Supabase has not been configured.'}
  const client=getSupabaseServerClient()
  const {data:result,error}=await client.auth.setSession({access_token:data.accessToken,refresh_token:data.refreshToken})
  if(error||!result.session)return {ok:false,error:'The authentication link is invalid or has expired.'}
  saveSession(result.session);return {ok:true,error:null}
})

export const requestPasswordReset=createServerFn({method:'POST'}).validator((value:{email:string})=>value).handler(async({data})=>{
  if(!configured())return {ok:false,error:'Supabase has not been configured.'}
  const siteUrl=process.env.APP_URL??'http://localhost:5173'
  const {error}=await getSupabaseServerClient().auth.resetPasswordForEmail(data.email.trim().toLowerCase(),{redirectTo:`${siteUrl}/reset-password`})
  return error?{ok:false,error:cleanAuthError(error)}:{ok:true,error:null}
})

export const updatePassword=createServerFn({method:'POST'}).validator((value:{password:string})=>value).handler(async({data})=>{
  if(data.password.length<8)return {ok:false,error:'Use at least eight characters.'}
  const token=getCookie(ACCESS_COOKIE);if(!token)return {ok:false,error:'Your reset session has expired.'}
  const {error}=await getSupabaseServerClient(token).auth.updateUser({password:data.password})
  return error?{ok:false,error:cleanAuthError(error)}:{ok:true,error:null}
})

export const signOut=createServerFn({method:'POST'}).handler(async()=>{
  if(configured()){const token=getCookie(ACCESS_COOKIE);if(token)await getSupabaseServerClient(token).auth.signOut()}
  clearSession();return {ok:true}
})

export async function requireRole(role:UserRole){const state=await getAuthState();if(!state.configured)return {allowed:true,state,demoMode:true};return {allowed:Boolean(state.user?.roles.includes(role)||state.user?.roles.includes('admin')),state,demoMode:false}}
