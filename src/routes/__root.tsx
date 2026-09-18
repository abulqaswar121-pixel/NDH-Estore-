import {createRootRouteWithContext,HeadContent,Outlet,Scripts} from '@tanstack/react-router'
import {QueryClient,QueryClientProvider} from '@tanstack/react-query'
import styles from '../styles.css?url'
import {AICustomerCare} from '@/components/AICustomerCare'
export const Route=createRootRouteWithContext<{queryClient:QueryClient}>()({head:()=>({meta:[{charSet:'utf-8'},{name:'viewport',content:'width=device-width,initial-scale=1'},{title:'NDH Estore — Commerce, beautifully simple'},{name:'description',content:'Launch and grow an African business globally with NDH Estore.'}],links:[{rel:'stylesheet',href:styles},{rel:'icon',type:'image/png',href:'/ndh-logo.png'}]}),component:Root})
function Root(){const {queryClient}=Route.useRouteContext();return <html lang="en"><head><HeadContent/></head><body><QueryClientProvider client={queryClient}><Outlet/><AICustomerCare/></QueryClientProvider><Scripts/></body></html>}
