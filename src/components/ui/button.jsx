import { forwardRef } from 'react'
import { cn } from '../../lib/utils'

const variants = {
  default: 'bg-primary text-primary-foreground shadow-sm shadow-primary/15 hover:-translate-y-px hover:bg-primary/90 hover:shadow-md hover:shadow-primary/20',
  secondary: 'bg-secondary text-secondary-foreground shadow-sm hover:-translate-y-px hover:bg-secondary/80',
  outline: 'border border-input bg-background/80 shadow-sm hover:-translate-y-px hover:bg-accent hover:text-accent-foreground',
  ghost: 'hover:bg-accent hover:text-accent-foreground',
  destructive: 'bg-destructive text-destructive-foreground shadow-sm shadow-destructive/15 hover:-translate-y-px hover:bg-destructive/90 hover:shadow-md',
  link: 'text-primary underline-offset-4 hover:underline',
}

const sizes = {
  default: 'h-10 px-4 py-2',
  sm: 'h-9 rounded-md px-3 text-xs',
  lg: 'h-11 rounded-lg px-6',
  icon: 'h-10 w-10',
}

export const Button = forwardRef(function Button({ className, variant = 'default', size = 'default', type = 'button', ...props }, ref) {
  return (
    <button
      ref={ref}
      type={type}
      className={cn(
        'inline-flex items-center justify-center gap-2 whitespace-nowrap rounded-xl text-sm font-bold transition-all duration-200 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring disabled:pointer-events-none disabled:opacity-50 active:translate-y-0',
        variants[variant], sizes[size], className,
      )}
      {...props}
    />
  )
})
