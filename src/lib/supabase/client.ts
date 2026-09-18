import {createClient,type SupabaseClient} from '@supabase/supabase-js'
import type {Database} from '@/types/database'

let browserClient:SupabaseClient<Database>|undefined

function publicConfiguration(){
  const url=import.meta.env.VITE_SUPABASE_URL as string|undefined
  const anonKey=import.meta.env.VITE_SUPABASE_ANON_KEY as string|undefined
  if(!url||!anonKey) return null
  return {url,anonKey}
}

export function isSupabaseConfigured(){return publicConfiguration()!==null}

export function getSupabaseBrowserClient(){
  const configuration=publicConfiguration()
  if(!configuration) throw new Error('Supabase is not configured. Add VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY to the environment.')
  browserClient??=createClient<Database>(configuration.url,configuration.anonKey,{auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:true}})
  return browserClient
}
