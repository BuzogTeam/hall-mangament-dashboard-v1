import { useState } from 'react'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { CalendarOff, CalendarCheck2 } from 'lucide-react'
import { toast } from 'sonner'
import { useAuth } from '../../context/AuthContext'
import { can } from '../../lib/permissions'
import { getErrorMessage } from '../../lib/utils'
import { lectureOccurrencesService } from '../../services/lectureOccurrencesService'
import { Button } from '../ui/button'
import { Textarea } from '../ui/textarea'
import { Label } from '../ui/label'
import { Dialog, DialogClose, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '../ui/dialog'

export function LectureOccurrenceAction({ row, compact = false }) {
  const { profile } = useAuth()
  const queryClient = useQueryClient()
  const [open, setOpen] = useState(false)
  const [reason, setReason] = useState('')
  const occurrenceCanceled = Boolean(row.occurrenceCanceled)
  const mutation = useMutation({
    mutationFn: () => lectureOccurrencesService.setCanceled(row.id, row.occurrenceDate, !occurrenceCanceled, reason),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['lecture-occurrence-overrides'] })
      queryClient.invalidateQueries({ queryKey: ['schedule'] })
      queryClient.invalidateQueries({ queryKey: ['dashboard'] })
      queryClient.invalidateQueries({ queryKey: ['conflicts'] })
      setOpen(false)
      setReason('')
      toast.success(occurrenceCanceled ? 'تمت إعادة المحاضرة لهذا التاريخ' : 'تم إلغاء المحاضرة لهذا التاريخ فقط')
    },
    onError: (error) => {
      setOpen(false)
      toast.error(getErrorMessage(error, 'تعذر تحديث حالة المحاضرة لهذا التاريخ'))
    },
  })
  if (!row.occurrenceDate || row.canceled || !can(profile, 'lectures.cancel_occurrence')) return null
  return <>
    <Button variant="ghost" size={compact ? 'icon' : 'sm'} className={occurrenceCanceled ? 'h-8 text-emerald-600' : 'h-8 text-rose-600'} onClick={(event) => { event.preventDefault(); event.stopPropagation(); setReason(''); setOpen(true) }} disabled={mutation.isPending} title={occurrenceCanceled ? 'إعادة المحاضرة لهذا التاريخ' : 'إلغاء لهذا التاريخ'} data-occurrence-date={row.occurrenceDate}>{occurrenceCanceled ? <><CalendarCheck2 className="h-3.5 w-3.5" />{compact ? null : 'إعادة لهذا اليوم'}</> : <><CalendarOff className="h-3.5 w-3.5" />{compact ? null : 'إلغاء لهذا اليوم'}</>}</Button>
    <Dialog open={open} onOpenChange={setOpen}><DialogContent className="max-w-md"><DialogClose onClick={() => setOpen(false)} /><DialogHeader><DialogTitle>{occurrenceCanceled ? 'إعادة المحاضرة لهذا التاريخ' : 'إلغاء المحاضرة لهذا التاريخ'}</DialogTitle><DialogDescription>{occurrenceCanceled ? `ستعود المحاضرة إلى جدول ${row.occurrenceDate} بعد فحص حجوزات القاعة والتعارضات.` : `سيتم إلغاء occurrence بتاريخ ${row.occurrenceDate} فقط. ستبقى المحاضرة الأسبوعية للأيام التالية.`}</DialogDescription></DialogHeader><div className="space-y-2"><Label htmlFor={`occurrence-reason-${row.id}-${row.occurrenceDate}`}>سبب العملية <span className="text-rose-500">*</span></Label><Textarea id={`occurrence-reason-${row.id}-${row.occurrenceDate}`} value={reason} onChange={(event) => setReason(event.target.value)} maxLength={500} placeholder="مثال: فعالية جامعية أو تعويض في موعد آخر" /><p className="text-[11px] text-muted-foreground">اكتب سببًا من 3 أحرف على الأقل لحفظه في سجل الاستثناء.</p></div><DialogFooter><Button variant="outline" onClick={() => setOpen(false)} disabled={mutation.isPending}>إلغاء</Button><Button variant={occurrenceCanceled ? 'default' : 'destructive'} onClick={() => mutation.mutate()} disabled={mutation.isPending || reason.trim().length < 3}>{mutation.isPending ? 'جارٍ التحقق…' : occurrenceCanceled ? 'إعادة لهذا اليوم' : 'تأكيد الإلغاء'}</Button></DialogFooter></DialogContent></Dialog>
  </>
}
