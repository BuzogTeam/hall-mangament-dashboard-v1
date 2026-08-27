import { AlertTriangle } from 'lucide-react'
import { Button } from '../ui/button'
import { Dialog, DialogClose, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '../ui/dialog'

export function ConfirmDialog({ open, onOpenChange, title = 'تأكيد العملية', description, confirmLabel = 'تأكيد الحذف', loading = false, onConfirm, destructive = true }) {
  return <Dialog open={open} onOpenChange={onOpenChange}><DialogContent className="max-w-md"><DialogClose onClick={() => onOpenChange?.(false)} /><DialogHeader><div className="mb-2 flex h-11 w-11 items-center justify-center rounded-xl bg-amber-500/10 text-amber-600"><AlertTriangle className="h-5 w-5" /></div><DialogTitle>{title}</DialogTitle><DialogDescription>{description || 'هل أنت متأكد من تنفيذ هذه العملية؟ لا يمكن التراجع عن هذا الإجراء.'}</DialogDescription></DialogHeader><DialogFooter><Button variant="outline" onClick={() => onOpenChange?.(false)} disabled={loading}>إلغاء</Button><Button variant={destructive ? 'destructive' : 'default'} onClick={onConfirm} disabled={loading}>{loading ? 'جارٍ التنفيذ…' : confirmLabel}</Button></DialogFooter></DialogContent></Dialog>
}
