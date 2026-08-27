import { forwardRef } from 'react'
import { cn } from '../../lib/utils'

export const Input = forwardRef(function Input({ className, type = 'text', ...props }, ref) {
  return (
    <input
      ref={ref}
      type={type}
      className={cn('flex h-11 w-full rounded-xl border border-input bg-background/80 px-3 py-2.5 text-sm outline-none shadow-sm transition-all placeholder:text-muted-foreground focus:border-primary focus:bg-background focus:ring-4 focus:ring-primary/10 disabled:cursor-not-allowed disabled:opacity-50', className)}
      {...props}
    />
  )
})
