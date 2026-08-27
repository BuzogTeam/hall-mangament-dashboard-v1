import { useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Ban, History, RotateCcw } from 'lucide-react'
import { toast } from 'sonner'
import { useAuth } from '../../context/AuthContext'
import { can } from '../../lib/permissions'
import { getErrorMessage } from '../../lib/utils'
import { lecturesService } from '../../services/lecturesService'
import { lectureHistoryService } from '../../services/lectureHistoryService'
import { Button } from '../ui/button'
import { Textarea } from '../ui/textarea'
import { Label } from '../ui/label'
import { Badge } from '../ui/badge'
import { Dialog, DialogClose, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '../ui/dialog'
import { EmptyState } from '../common/EmptyState'
import { ErrorState } from '../common/ErrorState'
import { LoadingState } from '../common/LoadingState'

export function LectureLifecycleAction({ row }) {
  const { profile } = useAuth()
  const queryClient = useQueryClient()
  const [open, setOpen] = useState(false)
  const [reason, setReason] = useState('')
  const mutation = useMutation({
    mutationFn: () => lecturesService.toggleCanceled(row.id, !row.canceled, reason),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['lectures'] })
      queryClient.invalidateQueries({ queryKey: ['schedule'] })
      queryClient.invalidateQueries({ queryKey: ['dashboard'] })
      queryClient.invalidateQueries({ queryKey: ['reports'] })
      queryClient.invalidateQueries({ queryKey: ['conflicts'] })
      queryClient.invalidateQueries({ queryKey: ['lecture-history', row.id] })
      setOpen(false)
      setReason('')
      toast.success(row.canceled ? 'تمت إعادة تفعيل المحاضرة' : 'تم إلغاء المحاضرة')
    },
    onError: (error) => {
      setOpen(false)
      toast.error(getErrorMessage(error, row.canceled ? 'تعذر إعادة تفعيل المحاضرة بسبب تعارض أو صلاحية غير كافية.' : 'تعذر إلغاء المحاضرة'))
    },
  })
  if (!can(profile, 'lectures.cancel')) return null
  const reactivating = row.canceled
  return <>
    <Button variant="ghost" size="sm" className={reactivating ? 'h-8 text-emerald-600' : 'h-8 text-rose-600'} onClick={() => { setReason(''); setOpen(true) }} disabled={mutation.isPending}>{reactivating ? <><RotateCcw className="h-3.5 w-3.5" />تفعيل</> : <><Ban className="h-3.5 w-3.5" />إلغاء</>}</Button>
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogContent className="max-w-md">
        <DialogClose onClick={() => setOpen(false)} />
        <DialogHeader>
          <DialogTitle>{reactivating ? 'إعادة تفعيل المحاضرة' : 'إلغاء المحاضرة'}</DialogTitle>
          <DialogDescription>{reactivating ? 'سيتم فحص القاعة والمدرس والدفعة داخل قاعدة البيانات. إذا وجد تعارض فلن تتغير الحالة.' : 'سيتم حفظ المحاضرة وتغيير حالتها إلى ملغاة دون حذفها من قاعدة البيانات.'}</DialogDescription>
        </DialogHeader>
        <div className="space-y-2">
          <Label htmlFor={`lecture-reason-${row.id}`}>سبب العملية <span className="text-rose-500">*</span></Label>
          <Textarea id={`lecture-reason-${row.id}`} value={reason} onChange={(event) => setReason(event.target.value)} maxLength={500} placeholder={reactivating ? 'مثال: تم حل التعارض مع القاعة' : 'مثال: إجازة المدرس أو فعالية جامعية'} />
          <p className="text-[11px] text-muted-foreground">اكتب سببًا مختصرًا (3 أحرف على الأقل) ليتم حفظه في سجل حالة المحاضرة.</p>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => setOpen(false)} disabled={mutation.isPending}>إلغاء</Button>
          <Button variant={reactivating ? 'default' : 'destructive'} onClick={() => mutation.mutate()} disabled={mutation.isPending || reason.trim().length < 3}>{mutation.isPending ? 'جارٍ التحقق…' : reactivating ? 'تفعيل المحاضرة' : 'تأكيد الإلغاء'}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  </>
}

export function LectureHistoryButton({ lecture }) {
  const [open, setOpen] = useState(false)
  const query = useQuery({ queryKey: ['lecture-history', lecture.id], queryFn: () => lectureHistoryService.list(lecture.id), enabled: open, staleTime: 15_000 })
  return <>
    <Button variant="ghost" size="icon" className="h-8 w-8 text-muted-foreground hover:text-primary" onClick={() => setOpen(true)} title="سجل الحالة"><History className="h-4 w-4" /></Button>
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogContent className="max-w-lg">
        <DialogClose onClick={() => setOpen(false)} />
        <DialogHeader><DialogTitle>سجل حالة المحاضرة</DialogTitle><DialogDescription>{lecture.subject?.title || 'محاضرة'} · يحتفظ النظام بتاريخ الإلغاء وإعادة التفعيل.</DialogDescription></DialogHeader>
        {query.isLoading ? <LoadingState rows={3} /> : query.isError ? <ErrorState error={query.error} onRetry={() => query.refetch()} /> : query.data?.length ? <div className="space-y-2">{query.data.map((item) => <div key={item.id} className="rounded-xl border border-border p-3"><div className="flex flex-wrap items-center justify-between gap-2"><Badge variant={item.new_canceled ? 'danger' : 'success'}>{item.new_canceled ? 'تم الإلغاء' : 'تمت إعادة التفعيل'}</Badge><span className="text-xs text-muted-foreground">{new Date(item.changed_at).toLocaleString('ar-YE')}</span></div><p className="mt-2 text-xs text-muted-foreground">المستخدم: <span dir="ltr" className="font-mono">{item.changed_by ? `${item.changed_by.slice(0, 8)}…` : 'غير معروف'}</span></p>{item.reason ? <p className="mt-1 text-sm leading-6">{item.reason}</p> : null}</div>)}</div> : <EmptyState title="لا يوجد سجل تغييرات" description="ستظهر هنا عمليات الإلغاء وإعادة التفعيل بعد تشغيل Migration السجل." />}
        <DialogFooter><Button variant="outline" onClick={() => setOpen(false)}>إغلاق</Button></DialogFooter>
      </DialogContent>
    </Dialog>
  </>
}
