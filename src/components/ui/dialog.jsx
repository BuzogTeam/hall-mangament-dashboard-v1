import { useEffect } from 'react'
import { X } from 'lucide-react'
import { cn } from '../../lib/utils'

export function Dialog({ open, onOpenChange, children }) {
  useEffect(() => {
    if (!open) return undefined
    const onKeyDown = (event) => { if (event.key === 'Escape') onOpenChange?.(false) }
    document.addEventListener('keydown', onKeyDown)
    const original = document.body.style.overflow
    document.body.style.overflow = 'hidden'
    return () => { document.removeEventListener('keydown', onKeyDown); document.body.style.overflow = original }
  }, [open, onOpenChange])
  if (!open) return null
  return <div className="fixed inset-0 z-50 flex items-center justify-center p-4"><div className="absolute inset-0 bg-slate-950/50 backdrop-blur-sm" onMouseDown={() => onOpenChange?.(false)} />{children}</div>
}

export function DialogContent({ className, children }) {
  return <div role="dialog" aria-modal="true" className={cn('relative z-10 max-h-[92vh] w-full max-w-lg overflow-y-auto rounded-2xl border border-border bg-card p-6 shadow-2xl animate-fade-in', className)} onMouseDown={(event) => event.stopPropagation()}>{children}</div>
}
export function DialogHeader({ className, ...props }) { return <div className={cn('mb-5 flex flex-col gap-1.5', className)} {...props} /> }
export function DialogTitle({ className, ...props }) { return <h2 className={cn('text-lg font-bold', className)} {...props} /> }
export function DialogDescription({ className, ...props }) { return <p className={cn('text-sm leading-6 text-muted-foreground', className)} {...props} /> }
export function DialogFooter({ className, ...props }) { return <div className={cn('mt-6 flex flex-col-reverse gap-2 sm:flex-row sm:justify-start', className)} {...props} /> }
export function DialogClose({ onClick }) { return <button type="button" aria-label="إغلاق" onClick={onClick} className="absolute left-4 top-4 rounded-md p-1.5 text-muted-foreground hover:bg-accent hover:text-foreground"><X className="h-4 w-4" /></button> }
