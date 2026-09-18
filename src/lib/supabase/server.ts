import {createClient} from '@supabase/supabase-js'
import type {Database} from '@/types/database'

function required(name:string){
  const value=process.env[name]
  if(!value) throw new Error(`Missing required server environment variable: ${name}`)
  return value
}

export function getSupabaseServerClient(accessToken?:string){
  const url=required('VITE_SUPABASE_URL')
  const anonKey=required('VITE_SUPABASE_ANON_KEY')
  return createClient<Database>(url,anonKey,{global:{headers:accessToken?{Authorization:`Bearer ${accessToken}`}:{}} ,auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}})
}

export function getSupabaseAdminClient(){
  const url=required('VITE_SUPABASE_URL')
  const serviceRoleKey=required('SUPABASE_SERVICE_ROLE_KEY')
  return createClient<Database>(url,serviceRoleKey,{auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}})
}
