import { cn } from '../../lib/utils'
export function Alert({ variant = 'default', className, children }) {
  return <div className={cn('rounded-xl border p-4 text-sm', variant === 'destructive' ? 'border-rose-200 bg-rose-50 text-rose-700 dark:border-rose-900 dark:bg-rose-950/30 dark:text-rose-300' : 'border-border bg-muted/50 text-foreground', className)}>{children}</div>
}
