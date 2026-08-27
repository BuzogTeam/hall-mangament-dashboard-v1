import { forwardRef } from 'react'
import { cn } from '../../lib/utils'

export const Textarea = forwardRef(function Textarea({ className, ...props }, ref) {
  return <textarea ref={ref} className={cn('min-h-24 w-full rounded-xl border border-input bg-background/80 px-3 py-2.5 text-sm outline-none shadow-sm transition-all placeholder:text-muted-foreground focus:border-primary focus:bg-background focus:ring-4 focus:ring-primary/10', className)} {...props} />
})
