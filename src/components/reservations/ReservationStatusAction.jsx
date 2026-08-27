import { useState } from 'react'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { Ban, CheckCircle2 } from 'lucide-react'
import { toast } from 'sonner'
import { useAuth } from '../../context/AuthContext'
import { can } from '../../lib/permissions'
import { getErrorMessage } from '../../lib/utils'
import { reservationsService } from '../../services/reservationsService'
import { Button } from '../ui/button'
import { Textarea } from '../ui/textarea'
import { Label } from '../ui/label'
import { Dialog, DialogClose, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '../ui/dialog'

export function ReservationStatusAction({ row }) {
  const { profile } = useAuth()
  const queryClient = useQueryClient()
  const [open, setOpen] = useState(false)
  const [reason, setReason] = useState('')
  const active = row.status === 'active'
  const mutation = useMutation({
    mutationFn: () => reservationsService.setStatus(row.id, active ? 'canceled' : 'active', reason),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['hall-reservations'] })
      queryClient.invalidateQueries({ queryKey: ['halls'] })
      queryClient.invalidateQueries({ queryKey: ['lectures'] })
      queryClient.invalidateQueries({ queryKey: ['schedule'] })
      queryClient.invalidateQueries({ queryKey: ['dashboard'] })
      setOpen(false)
      setReason('')
      toast.success(active ? 'تم إلغاء الحجز' : 'تم تفعيل الحجز')
    },
    onError: (error) => {
      setOpen(false)
      toast.error(getErrorMessage(error, 'تعذر تحديث حالة الحجز'))
    },
  })
  if (!can(profile, 'hall_reservations.cancel')) return null
  return <>
    <Button variant="ghost" size="sm" className={active ? 'h-8 text-rose-600' : 'h-8 text-emerald-600'} onClick={() => { setReason(''); setOpen(true) }} disabled={mutation.isPending}>{active ? <><Ban className="h-3.5 w-3.5" />إلغاء</> : <><CheckCircle2 className="h-3.5 w-3.5" />تفعيل</>}</Button>
    <Dialog open={open} onOpenChange={setOpen}><DialogContent className="max-w-md"><DialogClose onClick={() => setOpen(false)} /><DialogHeader><DialogTitle>{active ? 'إلغاء حجز القاعة' : 'تفعيل حجز القاعة'}</DialogTitle><DialogDescription>{active ? 'سيتم الاحتفاظ بالحجز في السجل وتغيير حالته إلى ملغى.' : 'سيتم فحص الحجوزات والمحاضرات المتداخلة قبل تفعيل الحجز.'}</DialogDescription></DialogHeader><div className="space-y-2"><Label htmlFor={`reservation-reason-${row.id}`}>سبب العملية (اختياري)</Label><Textarea id={`reservation-reason-${row.id}`} value={reason} onChange={(event) => setReason(event.target.value)} maxLength={500} placeholder="مثال: انتهت الفعالية الجامعية" /></div><DialogFooter><Button variant="outline" onClick={() => setOpen(false)} disabled={mutation.isPending}>إغلاق</Button><Button variant={active ? 'destructive' : 'default'} onClick={() => mutation.mutate()} disabled={mutation.isPending}>{mutation.isPending ? 'جارٍ التحقق…' : active ? 'تأكيد الإلغاء' : 'تأكيد التفعيل'}</Button></DialogFooter></DialogContent></Dialog>
  </>
}
