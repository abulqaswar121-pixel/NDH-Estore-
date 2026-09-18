import {createRouter} from '@tanstack/react-router'
import {QueryClient} from '@tanstack/react-query'
import {routeTree} from './routeTree.gen'
export function getRouter(){const queryClient=new QueryClient({defaultOptions:{queries:{staleTime:30_000,retry:1}}});return createRouter({routeTree,scrollRestoration:true,defaultPreload:'intent',context:{queryClient}})}
declare module '@tanstack/react-router'{interface Register{router:ReturnType<typeof getRouter>}}
