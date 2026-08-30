import { useMemo } from 'react'
import { useQuery } from '@tanstack/react-query'
import { useSearchParams } from 'react-router-dom'
import { CalendarClock, DoorOpen, LockKeyhole, ShieldCheck } from 'lucide-react'
import { z } from 'zod'
import { CrudResourcePage } from '../../components/common/CrudResourcePage'
import { FormField } from '../../components/common/FormField'
import { StatusBadge } from '../../components/common/StatusBadge'
import { Input } from '../../components/ui/input'
import { Select } from '../../components/ui/select'
import { Textarea } from '../../components/ui/textarea'
import { Card, CardContent } from '../../components/ui/card'
import { Alert } from '../../components/ui/alert'
import { ReservationStatusAction } from '../../components/reservations/ReservationStatusAction'
import { reservationsService } from '../../services/reservationsService'
import { lecturesService } from '../../services/lecturesService'
import { hallsService } from '../../services/hallsService'
import { departmentsService } from '../../services/departmentsService'
import { levelsService } from '../../services/levelsService'
import { departmentLevelsService } from '../../services/departmentLevelsService'
import { metadataService } from '../../services/metadataService'
import { DAY_OPTIONS, formatTime, getDayLabel, getLectureStatus, isReservationActiveNow } from '../../lib/utils'
import { isDepartmentManager } from '../../lib/permissions'
import { useAuth } from '../../context/AuthContext'
import { usePageTitle } from '../../hooks/usePageTitle'

const optionalId = z.preprocess((value) => value === '' || value === null || value === undefined ? undefined : value, z.coerce.number().positive().optional())

function createReservationSchema(isManager) {
  return z.object({
    hall_id: z.coerce.number().positive('اختر القاعة'),
    mode: z.enum(['recurring', 'date']),
    reservation_date: z.string().optional(),
    day_of_week: z.string().optional(),
    department_id: optionalId,
    level_id: optionalId,
    start_at: z.string().min(1, 'وقت البداية مطلوب'),
    end_at: z.string().min(1, 'وقت النهاية مطلوب'),
    reason: z.string().max(500, 'السبب طويل').optional(),
    notes: z.string().max(2000, 'الملاحظات طويلة').optional(),
  }).superRefine((values, context) => {
    if (values.mode === 'recurring' && !values.day_of_week) context.addIssue({ code: z.ZodIssueCode.custom, path: ['day_of_week'], message: 'اختر يوم الحجز' })
    if (values.mode === 'date' && !values.reservation_date) context.addIssue({ code: z.ZodIssueCode.custom, path: ['reservation_date'], message: 'اختر تاريخ الحجز' })
    if (values.start_at && values.end_at && values.start_at >= values.end_at) context.addIssue({ code: z.ZodIssueCode.custom, path: ['end_at'], message: 'يجب أن يكون وقت النهاية بعد البداية' })
    if (isManager) {
      if (values.mode !== 'date') context.addIssue({ code: z.ZodIssueCode.custom, path: ['mode'], message: 'مدير القسم يدير الحجوزات المؤقتة فقط' })
      if (!values.department_id) context.addIssue({ code: z.ZodIssueCode.custom, path: ['department_id'], message: 'القسم المرتبط بالـ Scope مطلوب' })
      if (!values.level_id) context.addIssue({ code: z.ZodIssueCode.custom, path: ['level_id'], message: 'اختر مستوى من Scope الخاص بك' })
    }
  })
}

const reservationAdapter = {
  list: reservationsService.list,
  create: (payload) => reservationsService.save(payload),
  update: (id, payload) => reservationsService.save(payload, id),
  remove: reservationsService.remove,
}

export function Reservations() {
  usePageTitle('حجوزات القاعات')
  const { profile } = useAuth()
  const [searchParams] = useSearchParams()
  const isManager = isDepartmentManager(profile)
  const searchKey = searchParams.toString()
  const halls = useQuery({ queryKey: ['halls', 'reservations'], queryFn: hallsService.list })
  const reservations = useQuery({ queryKey: ['hall-reservations'], queryFn: reservationsService.list })
  const lectures = useQuery({ queryKey: ['lectures', 'reservation-status'], queryFn: lecturesService.list })
  const metadata = useQuery({ queryKey: ['metadata'], queryFn: metadataService.getOptions })
  const departments = useQuery({ queryKey: ['departments', 'reservation-scope'], queryFn: departmentsService.list, enabled: isManager })
  const levels = useQuery({ queryKey: ['levels', 'reservation-scope'], queryFn: levelsService.list, enabled: isManager })
  const departmentLevels = useQuery({ queryKey: ['department-levels', 'reservation-scope'], queryFn: departmentLevelsService.list, enabled: isManager })

  const dayOptions = useMemo(() => {
    const values = metadata.data?.days?.length ? metadata.data.days : DAY_OPTIONS.map((day) => day.value)
    return values.map((value) => DAY_OPTIONS.find((day) => day.value === value) || { value, label: value, short: value })
  }, [metadata.data?.days])
  const hallOptions = halls.data || []
  const department = (departments.data || []).find((item) => String(item.id) === String(profile?.department_id))
  const scopeLevelOptions = useMemo(() => {
    const mappedIds = new Set((departmentLevels.data || [])
      .filter((item) => String(item.department_id) === String(profile?.department_id) && item.is_active !== false)
      .map((item) => String(item.level_id)))
    return (levels.data || []).filter((level) => mappedIds.has(String(level.id)))
  }, [departmentLevels.data, levels.data, profile?.department_id])
  const requestedLevelId = searchParams.get('level_id')
  const defaultLevelId = scopeLevelOptions.some((level) => String(level.id) === String(requestedLevelId)) ? requestedLevelId : scopeLevelOptions.length === 1 ? String(scopeLevelOptions[0].id) : ''
  const defaultValues = useMemo(() => ({
    hall_id: searchParams.get('hall_id') || '',
    mode: isManager || searchParams.get('mode') === 'date' ? 'date' : 'recurring',
    reservation_date: searchParams.get('reservation_date') || '',
    day_of_week: searchParams.get('day_of_week') || dayOptions[0]?.value || 'احد',
    department_id: isManager && profile?.department_id ? String(profile.department_id) : '',
    level_id: isManager ? defaultLevelId : '',
    start_at: searchParams.get('start_at') || '08:00',
    end_at: searchParams.get('end_at') || '10:00',
    reason: '',
    notes: '',
  }), [dayOptions, defaultLevelId, isManager, profile?.department_id, searchKey])
  const reservationSchema = useMemo(() => createReservationSchema(isManager), [isManager])
  const hallStatusCounts = useMemo(() => hallOptions.reduce((counts, hall) => {
    if (hall.booking) counts.unavailable += 1
    else if ((reservations.data || []).some((reservation) => reservation.hall_id === hall.id && isReservationActiveNow(reservation))) counts.reserved += 1
    else if ((lectures.data || []).some((lecture) => lecture.hall_id === hall.id && !lecture.canceled && getLectureStatus(lecture) === 'live')) counts.occupied += 1
    else counts.available += 1
    return counts
  }, { available: 0, occupied: 0, reserved: 0, unavailable: 0 }), [hallOptions, reservations.data, lectures.data])

  const mapSubmitValues = (values, editingRow) => ({
    hall_id: Number(values.hall_id),
    reservation_date: values.mode === 'date' ? values.reservation_date || null : null,
    day_of_week: values.mode === 'recurring' ? values.day_of_week || null : null,
    // Global roles preserve an existing scoped reservation when editing it;
    // newly created global reservations remain unscoped.
    department_id: isManager ? Number(values.department_id || profile?.department_id) : editingRow?.department_id || null,
    level_id: isManager ? Number(values.level_id) : editingRow?.level_id || null,
    start_at: values.start_at,
    end_at: values.end_at,
    reason: values.reason?.trim() || null,
    notes: values.notes?.trim() || null,
  })

  return <div className="page-enter">
    <HallStatusOverview counts={hallStatusCounts} />
    {isManager ? <Alert className="mb-5 border-primary/20 bg-primary/[.04] text-primary"><div className="flex items-start gap-3"><ShieldCheck className="mt-0.5 h-5 w-5 shrink-0" /><div><p className="font-black">إدارة الحجوزات المؤقتة ضمن Scope</p><p className="mt-1 text-xs leading-6">يمكنك إنشاء وتعديل وإلغاء حجز ليوم واحد فقط للمستوى المرتبط بصلاحياتك. الحجوزات الأسبوعية وإدارة القاعات العامة متاحة للأدوار الإدارية المخصصة.</p></div></div></Alert> : null}
    {searchParams.get('reservation_date') && searchParams.get('hall_id') ? <Alert className="mb-5 border-emerald-200 bg-emerald-50 text-emerald-800 dark:border-emerald-900 dark:bg-emerald-950/20 dark:text-emerald-300"><div className="flex items-start gap-3"><CalendarClock className="mt-0.5 h-5 w-5 shrink-0" /><div><p className="font-black">تم تمرير تاريخ ووقت occurrence من Schedule</p><p className="mt-1 text-xs leading-6">سيتم استخدام القاعة والتاريخ والوقت المحدد مسبقًا، ويمكنك مراجعة المستوى والسبب قبل إنشاء الحجز.</p></div></div></Alert> : null}
    <CrudResourcePage
      title="حجوزات القاعات"
      description={isManager ? 'أنشئ حجزًا مؤقتًا بعد إلغاء occurrence، ضمن القسم والمستوى المسموحين لك.' : 'أنشئ حجزًا مؤقتًا ليوم واحد أو حجزًا متكررًا، مع منع التعارض مع المحاضرات والحجوزات.'}
      icon={LockKeyhole}
      resource="hall_reservations"
      queryKey="hall-reservations"
      service={reservationAdapter}
      schema={reservationSchema}
      defaultValues={defaultValues}
      searchPlaceholder="ابحث بالقاعة أو السبب أو النطاق…"
      searchFields={[(row) => row.hall?.title, (row) => row.hall?.building?.title, 'reason', 'notes', (row) => row.day_of_week, (row) => row.reservation_date, (row) => row.department?.title, (row) => row.level?.title]}
      filterData={(rows, filters) => rows.filter((row) => (!filters.hall || String(row.hall_id) === String(filters.hall)) && (!filters.status || row.status === filters.status))}
      renderToolbar={({ filters, setFilters }) => <div className="flex flex-wrap gap-2"><Select value={filters.hall || ''} onChange={(event) => setFilters((current) => ({ ...current, hall: event.target.value }))} className="h-9 w-auto min-w-32 text-xs"><option value="">كل القاعات</option>{hallOptions.map((hall) => <option key={hall.id} value={hall.id}>{hall.title} — {hall.building?.title}</option>)}</Select><Select value={filters.status || ''} onChange={(event) => setFilters((current) => ({ ...current, status: event.target.value }))} className="h-9 w-auto min-w-28 text-xs"><option value="">كل الحالات</option><option value="active">نشطة</option><option value="canceled">ملغاة</option></Select></div>}
      columns={[{ key: 'hall', header: 'القاعة', cell: (row) => <div><p className="font-bold">{row.hall?.title || `#${row.hall_id}`}</p><p className="text-[11px] text-muted-foreground">{row.hall?.building?.title || '—'}</p></div> }, { key: 'scope', header: 'النطاق', cell: (row) => row.department?.title ? <span className="text-xs font-semibold">{row.department.abbreviation || row.department.title} — {row.level?.title || `المستوى #${row.level_id}`}</span> : <span className="text-xs text-muted-foreground">عام</span> }, { key: 'schedule', header: 'النطاق الزمني', cell: (row) => <div><p className="font-semibold">{row.reservation_date ? new Date(`${row.reservation_date}T00:00:00`).toLocaleDateString('ar-YE') : `${getDayLabel(row.day_of_week)} (متكرر)`}</p><p className="mt-1 font-mono text-xs text-muted-foreground">{formatTime(row.start_at)} — {formatTime(row.end_at)}</p></div> }, { key: 'reason', header: 'السبب / الملاحظات', cell: (row) => <div className="max-w-56"><p className="truncate text-xs font-semibold">{row.reason || 'بدون سبب'}</p>{row.notes ? <p className="mt-1 truncate text-[11px] text-muted-foreground">{row.notes}</p> : null}</div> }, { key: 'status', header: 'الحالة', cell: (row) => <StatusBadge status={row.status === 'active' ? 'reserved' : 'canceled'} label={row.status === 'active' ? 'نشط' : 'ملغى'} /> }, { key: 'created_at', header: 'تاريخ الإنشاء', cell: (row) => row.created_at ? new Date(row.created_at).toLocaleDateString('ar-YE') : '—' }]}
      renderFields={({ register, formState: { errors }, watch, setValue }) => <ReservationFields register={register} errors={errors} watch={watch} setValue={setValue} halls={hallOptions} dayOptions={dayOptions} isManager={isManager} department={department} scopeLevelOptions={scopeLevelOptions} profile={profile} />}
      mapFormValues={(row) => ({ hall_id: String(row.hall_id || ''), mode: row.reservation_date ? 'date' : 'recurring', reservation_date: row.reservation_date || '', day_of_week: row.day_of_week || dayOptions[0]?.value, department_id: row.department_id ? String(row.department_id) : isManager && profile?.department_id ? String(profile.department_id) : '', level_id: row.level_id ? String(row.level_id) : isManager ? defaultLevelId : '', start_at: row.start_at?.slice(0, 5) || '08:00', end_at: row.end_at?.slice(0, 5) || '10:00', reason: row.reason || '', notes: row.notes || '' })}
      mapSubmitValues={mapSubmitValues}
      showDelete={false}
      extraActions={({ row }) => row ? <ReservationStatusAction row={row} /> : null}
    />
  </div>
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

function ReservationFields({ register, errors, watch, setValue, halls, dayOptions, isManager, department, scopeLevelOptions, profile }) {
  const mode = watch('mode')
  const dateMode = isManager || mode === 'date'
  return <>
    <FormField label="القاعة" name="hall_id" required error={errors.hall_id}><Select id="hall_id" {...register('hall_id')}><option value="">اختر القاعة</option>{halls.map((hall) => <option key={hall.id} value={hall.id}>{hall.title} — {hall.building?.title}</option>)}</Select></FormField>
    <FormField label="نوع الحجز" name="mode" required error={errors.mode}><Select id="mode" {...register('mode')} onChange={(event) => { const next = event.target.value; setValue('mode', next, { shouldValidate: true }); if (next === 'date') setValue('day_of_week', ''); else setValue('reservation_date', '') }}><option value="date">حجز مؤقت ليوم واحد</option>{!isManager ? <option value="recurring">حجز قاعة أسبوعي ثابت ومتكرر</option> : null}</Select></FormField>
    {isManager ? <>
      <input type="hidden" {...register('department_id')} value={profile?.department_id ? String(profile.department_id) : ''} />
      <FormField label="القسم ضمن Scope" name="department_id" required error={errors.department_id}><Input id="department_id_display" value={department?.title ? `${department.title} — ${department.abbreviation || ''}` : `القسم #${profile?.department_id || '—'}`} readOnly aria-readonly="true" /></FormField>
      <FormField label="المستوى ضمن Scope" name="level_id" required error={errors.level_id}><Select id="level_id" {...register('level_id')}><option value="">اختر المستوى</option>{scopeLevelOptions.map((level) => <option key={level.id} value={level.id}>{level.title}</option>)}</Select>{!scopeLevelOptions.length ? <p className="mt-1 text-xs font-medium text-amber-700 dark:text-amber-300">لا توجد مستويات نشطة في Scope الحالي.</p> : null}</FormField>
    </> : null}
    {dateMode ? <FormField label="تاريخ الحجز" name="reservation_date" required error={errors.reservation_date}><Input id="reservation_date" type="date" {...register('reservation_date')} /></FormField> : <FormField label="يوم الحجز الأسبوعي" name="day_of_week" required error={errors.day_of_week}><Select id="day_of_week" {...register('day_of_week')}><option value="">اختر اليوم</option>{dayOptions.map((day) => <option key={day.value} value={day.value}>{day.label}</option>)}</Select></FormField>}
    <div className="grid gap-4 sm:grid-cols-2"><FormField label="وقت البداية" name="start_at" required error={errors.start_at}><Input id="start_at" type="time" {...register('start_at')} /></FormField><FormField label="وقت النهاية" name="end_at" required error={errors.end_at}><Input id="end_at" type="time" {...register('end_at')} /></FormField></div>
    <FormField label="السبب" name="reason" error={errors.reason}><Input id="reason" placeholder="مثال: فعالية جامعية أو صيانة" {...register('reason')} /></FormField>
    <FormField label="ملاحظات" name="notes" error={errors.notes}><Textarea id="notes" placeholder="تفاصيل إضافية عن الحجز" {...register('notes')} /></FormField>
    <div className="flex items-start gap-2 rounded-xl border border-blue-200 bg-blue-50 p-3 text-xs leading-6 text-blue-700 dark:border-blue-900 dark:bg-blue-950/25 dark:text-blue-300"><CalendarClock className="mt-0.5 h-4 w-4 shrink-0" />الحجز المؤقت لا يلغي المحاضرة تلقائيًا؛ إذا كانت هناك محاضرة في نفس التاريخ والوقت يجب إلغاء occurrence أولًا.</div>
  </>
}
