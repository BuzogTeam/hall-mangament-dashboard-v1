import { forwardRef } from 'react'
import { cn } from '../../lib/utils'

export const Select = forwardRef(function Select({ className, children, ...props }, ref) {
  return <select ref={ref} className={cn('select-control flex h-11 w-full appearance-none rounded-xl border border-input bg-background/80 px-3 py-2.5 text-sm outline-none shadow-sm transition-all focus:border-primary focus:bg-background focus:ring-4 focus:ring-primary/10', className)} {...props}>{children}</select>
})
