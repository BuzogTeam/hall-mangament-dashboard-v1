import { cn } from '../../lib/utils'

export function Card({ className, ...props }) {
  return <div className={cn('rounded-2xl border border-border/80 bg-card/95 text-card-foreground shadow-card', className)} {...props} />
}
export function CardHeader({ className, ...props }) { return <div className={cn('flex flex-col gap-1.5 p-5', className)} {...props} /> }
export function CardTitle({ className, ...props }) { return <h3 className={cn('text-base font-bold tracking-tight', className)} {...props} /> }
export function CardDescription({ className, ...props }) { return <p className={cn('text-sm text-muted-foreground', className)} {...props} /> }
export function CardContent({ className, ...props }) { return <div className={cn('p-5 pt-0', className)} {...props} /> }
