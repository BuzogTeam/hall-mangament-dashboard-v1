import { Inbox, Plus } from 'lucide-react'
import { Button } from '../ui/button'

export function EmptyState({ title = 'لا توجد بيانات', description = 'لا توجد عناصر لعرضها حاليًا.', actionLabel, onAction, icon: Icon = Inbox }) {
  return <div className="flex min-h-56 flex-col items-center justify-center rounded-2xl border border-dashed border-border bg-card/60 px-5 text-center"><div className="mb-3 flex h-12 w-12 items-center justify-center rounded-2xl bg-muted text-muted-foreground"><Icon className="h-6 w-6" /></div><h3 className="font-bold">{title}</h3><p className="mt-1 max-w-sm text-sm leading-6 text-muted-foreground">{description}</p>{actionLabel ? <Button className="mt-4" size="sm" onClick={onAction}><Plus className="h-4 w-4" />{actionLabel}</Button> : null}</div>
}
