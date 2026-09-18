import type {ButtonHTMLAttributes,HTMLAttributes,ReactNode} from 'react'
export function Button({className='',...p}:ButtonHTMLAttributes<HTMLButtonElement>){return <button className={`rounded-full bg-primary px-5 py-2.5 text-sm font-semibold text-primary-foreground hover:-translate-y-0.5 hover:shadow-lg disabled:opacity-50 ${className}`} {...p}/>}
export function Card({className='',...p}:HTMLAttributes<HTMLDivElement>){return <div className={`rounded-3xl border border-border bg-card ${className}`} {...p}/>}
export function Badge({children,className=''}:{children:ReactNode,className?:string}){return <span className={`inline-flex rounded-full bg-secondary px-3 py-1 text-xs font-semibold text-secondary-foreground ${className}`}>{children}</span>}
export function Input(p:React.InputHTMLAttributes<HTMLInputElement>){return <input {...p} className={`w-full rounded-xl border border-border bg-card px-4 py-3 outline-none focus:ring-2 focus:ring-primary/20 ${p.className||''}`}/>}
