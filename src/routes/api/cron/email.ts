import {createFileRoute} from '@tanstack/react-router'
import {dispatchEmailQueue} from '@/lib/email'
export const Route=createFileRoute('/api/cron/email')({server:{handlers:{POST:async({request})=>{const secret=request.headers.get('authorization')?.replace(/^Bearer\s+/i,'')??'';if(!process.env.EMAIL_DISPATCH_SECRET||secret!==process.env.EMAIL_DISPATCH_SECRET)return new Response('Unauthorized',{status:401});const result=await dispatchEmailQueue({data:{secret}});return Response.json(result,{status:result.ok?200:500})}}}})
