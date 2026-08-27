import { Plus } from 'lucide-react'
import { Button } from '../ui/button'

export function PageHeader({ title, description, eyebrow = 'إدارة النظام', icon: Icon, actionLabel, onAction, actionPermission = true, children }) {
  return (
    <div className="mb-7 flex flex-col gap-5 lg:flex-row lg:items-end lg:justify-between">
      <div className="flex items-start gap-3">
        {Icon ? <div className="relative mt-1 flex h-12 w-12 shrink-0 items-center justify-center overflow-hidden rounded-2xl bg-gradient-to-br from-primary/15 to-cyan-400/10 text-primary ring-1 ring-primary/10"><div className="absolute -left-3 -top-3 h-8 w-8 rounded-full bg-primary/10" /><Icon className="relative h-5 w-5" /></div> : null}
        <div>
          <p className="eyebrow mb-1.5">{eyebrow}</p>
          <h1 className="text-2xl font-black tracking-tight text-foreground sm:text-3xl">{title}</h1>
          {description ? <p className="mt-1.5 max-w-2xl text-sm leading-7 text-muted-foreground">{description}</p> : null}
        </div>
      </div>
      <div className="flex flex-wrap items-center gap-2">
        {children}
        {actionLabel && actionPermission ? <Button onClick={onAction}><Plus className="h-4 w-4" />{actionLabel}</Button> : null}
      </div>
    </div>
  )
}
