import { useMemo } from 'react'
import { useQuery } from '@tanstack/react-query'
import { CalendarClock, DoorOpen, LockKeyhole } from 'lucide-react'
import { z } from 'zod'
import { CrudResourcePage } from '../../components/common/CrudResourcePage'
import { FormField } from '../../components/common/FormField'
import { StatusBadge } from '../../components/common/StatusBadge'
import { Input } from '../../components/ui/input'
import { Select } from '../../components/ui/select'
import { Textarea } from '../../components/ui/textarea'
import { reservationsService } from '../../services/reservationsService'
import { lecturesService } from '../../services/lecturesService'
import { hallsService } from '../../services/hallsService'
import { metadataService } from '../../services/metadataService'
import { ReservationStatusAction } from '../../components/reservations/ReservationStatusAction'
import { DAY_OPTIONS, formatTime, getDayLabel, getLectureStatus, isReservationActiveNow } from '../../lib/utils'
import { usePageTitle } from '../../hooks/usePageTitle'
import { Card, CardContent } from '../../components/ui/card'

const reservationSchema = z.object({
  hall_id: z.coerce.number().positive('اختر القاعة'),
  day_of_week: z.string().min(1, 'اختر يوم الحجز'),
  start_at: z.string().min(1, 'وقت البداية مطلوب'),
  end_at: z.string().min(1, 'وقت النهاية مطلوب'),
  reason: z.string().max(500, 'السبب طويل').optional(),
  notes: z.string().max(2000, 'الملاحظات طويلة').optional(),
}).superRefine((values, context) => {
  if (values.start_at && values.end_at && values.start_at >= values.end_at) context.addIssue({ code: z.ZodIssueCode.custom, path: ['end_at'], message: 'يجب أن يكون وقت النهاية بعد البداية' })
})

const reservationAdapter = {
  list: reservationsService.list,
  create: (payload) => reservationsService.save(payload),
  update: (id, payload) => reservationsService.save(payload, id),
  remove: reservationsService.remove,
}

export function Reservations() {
  usePageTitle('حجوزات القاعات')
  const halls = useQuery({ queryKey: ['halls', 'reservations'], queryFn: hallsService.list })
  const reservations = useQuery({ queryKey: ['hall-reservations'], queryFn: reservationsService.list })
  const lectures = useQuery({ queryKey: ['lectures', 'reservation-status'], queryFn: lecturesService.list })
  const metadata = useQuery({ queryKey: ['metadata'], queryFn: metadataService.getOptions })
  const dayOptions = useMemo(() => {
    const values = metadata.data?.days?.length ? metadata.data.days : DAY_OPTIONS.map((day) => day.value)
    return values.map((value) => DAY_OPTIONS.find((day) => day.value === value) || { value, label: value, short: value })
  }, [metadata.data?.days])
  const hallOptions = halls.data || []
  const hallStatusCounts = useMemo(() => hallOptions.reduce((counts, hall) => {
    if (hall.booking) counts.unavailable += 1
    else if ((reservations.data || []).some((reservation) => reservation.hall_id === hall.id && isReservationActiveNow(reservation))) counts.reserved += 1
    else if ((lectures.data || []).some((lecture) => lecture.hall_id === hall.id && !lecture.canceled && getLectureStatus(lecture) === 'live')) counts.occupied += 1
    else counts.available += 1
    return counts
  }, { available: 0, occupied: 0, reserved: 0, unavailable: 0 }), [hallOptions, reservations.data, lectures.data])
  return <div className="page-enter"><HallStatusOverview counts={hallStatusCounts} /><CrudResourcePage title="حجوزات القاعات" description="أنشئ حجوزات أسبوعية متكررة، مع منع تعارضها مع الحجوزات والمحاضرات." icon={LockKeyhole} resource="hall_reservations" queryKey="hall-reservations" service={reservationAdapter} schema={reservationSchema} defaultValues={{ hall_id: '', day_of_week: dayOptions[0]?.value || 'احد', start_at: '08:00', end_at: '10:00', reason: '', notes: '' }} searchPlaceholder="ابحث بالقاعة أو السبب…" searchFields={[(row) => row.hall?.title, (row) => row.hall?.building?.title, 'reason', 'notes', (row) => row.day_of_week]} filterData={(rows, filters) => rows.filter((row) => (!filters.hall || String(row.hall_id) === String(filters.hall)) && (!filters.status || row.status === filters.status))} renderToolbar={({ filters, setFilters }) => <div className="flex flex-wrap gap-2"><Select value={filters.hall || ''} onChange={(event) => setFilters((current) => ({ ...current, hall: event.target.value }))} className="h-9 w-auto min-w-32 text-xs"><option value="">كل القاعات</option>{hallOptions.map((hall) => <option key={hall.id} value={hall.id}>{hall.title} — {hall.building?.title}</option>)}</Select><Select value={filters.status || ''} onChange={(event) => setFilters((current) => ({ ...current, status: event.target.value }))} className="h-9 w-auto min-w-28 text-xs"><option value="">كل الحالات</option><option value="active">نشطة</option><option value="canceled">ملغاة</option></Select></div>} columns={[{ key: 'hall', header: 'القاعة', cell: (row) => <div><p className="font-bold">{row.hall?.title || `#${row.hall_id}`}</p><p className="text-[11px] text-muted-foreground">{row.hall?.building?.title || '—'}</p></div> }, { key: 'schedule', header: 'النطاق الزمني', cell: (row) => <div><p className="font-semibold">{getDayLabel(row.day_of_week)} (متكرر)</p><p className="mt-1 font-mono text-xs text-muted-foreground">{formatTime(row.start_at)} — {formatTime(row.end_at)}</p></div> }, { key: 'reason', header: 'السبب / الملاحظات', cell: (row) => <div className="max-w-56"><p className="truncate text-xs font-semibold">{row.reason || 'بدون سبب'}</p>{row.notes ? <p className="mt-1 truncate text-[11px] text-muted-foreground">{row.notes}</p> : null}</div> }, { key: 'status', header: 'الحالة', cell: (row) => <StatusBadge status={row.status === 'active' ? 'reserved' : 'canceled'} label={row.status === 'active' ? 'نشط' : 'ملغى'} /> }, { key: 'created_at', header: 'تاريخ الإنشاء', cell: (row) => row.created_at ? new Date(row.created_at).toLocaleDateString('ar-YE') : '—' }]} renderFields={({ register, formState: { errors } }) => <ReservationFields register={register} errors={errors} halls={hallOptions} dayOptions={dayOptions} />} mapFormValues={(row) => ({ hall_id: String(row.hall_id || ''), day_of_week: row.day_of_week || dayOptions[0]?.value, start_at: row.start_at?.slice(0, 5) || '08:00', end_at: row.end_at?.slice(0, 5) || '10:00', reason: row.reason || '', notes: row.notes || '' })} mapSubmitValues={(values) => ({ hall_id: Number(values.hall_id), day_of_week: values.day_of_week, start_at: values.start_at, end_at: values.end_at, reason: values.reason?.trim() || null, notes: values.notes?.trim() || null })} showDelete={false} extraActions={({ row }) => row ? <ReservationStatusAction row={row} /> : null} /></div>
}

function HallStatusOverview({ counts }) {
  const items = [
    { key: 'available', label: 'متاحة', value: counts.available, tone: 'text-emerald-600 bg-emerald-500/10' },
    { key: 'occupied', label: 'مشغولة بمحاضرة', value: counts.occupied, tone: 'text-amber-600 bg-amber-500/10' },
    { key: 'reserved', label: 'محجوزة زمنيًا', value: counts.reserved, tone: 'text-violet-600 bg-violet-500/10' },
    { key: 'unavailable', label: 'غير متاحة إداريًا', value: counts.unavailable, tone: 'text-rose-600 bg-rose-500/10' },
  ]
  return <div className="mb-5 grid gap-3 sm:grid-cols-2 xl:grid-cols-4">{items.map((item) => <Card key={item.key}><CardContent className="flex items-center justify-between p-4"><div><p className="text-xs font-bold text-muted-foreground">{item.label}</p><p className="mt-1 text-2xl font-black">{item.value}</p></div><div className={`flex h-10 w-10 items-center justify-center rounded-xl ${item.tone}`}><DoorOpen className="h-5 w-5" /></div></CardContent></Card>)}</div>
}

function ReservationFields({ register, errors, halls, dayOptions }) {
  return <><FormField label="القاعة" name="hall_id" required error={errors.hall_id}><Select id="hall_id" {...register('hall_id')}><option value="">اختر القاعة</option>{halls.map((hall) => <option key={hall.id} value={hall.id}>{hall.title} — {hall.building?.title}</option>)}</Select></FormField><FormField label="يوم الحجز الأسبوعي" name="day_of_week" required error={errors.day_of_week}><Select id="day_of_week" {...register('day_of_week')}><option value="">اختر اليوم</option>{dayOptions.map((day) => <option key={day.value} value={day.value}>{day.label}</option>)}</Select></FormField><div className="grid gap-4 sm:grid-cols-2"><FormField label="وقت البداية" name="start_at" required error={errors.start_at}><Input id="start_at" type="time" {...register('start_at')} /></FormField><FormField label="وقت النهاية" name="end_at" required error={errors.end_at}><Input id="end_at" type="time" {...register('end_at')} /></FormField></div><FormField label="السبب" name="reason" error={errors.reason}><Input id="reason" placeholder="مثال: فعالية جامعية أو صيانة" {...register('reason')} /></FormField><FormField label="ملاحظات" name="notes" error={errors.notes}><Textarea id="notes" placeholder="تفاصيل إضافية عن الحجز" {...register('notes')} /></FormField><div className="flex items-start gap-2 rounded-xl border border-blue-200 bg-blue-50 p-3 text-xs leading-6 text-blue-700 dark:border-blue-900 dark:bg-blue-950/25 dark:text-blue-300"><CalendarClock className="mt-0.5 h-4 w-4 shrink-0" />سيتم فحص الحجز ضد الحجوزات الأسبوعية والمحاضرات النشطة في القاعة قبل الحفظ.</div></>
}
