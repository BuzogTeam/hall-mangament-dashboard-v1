import { useMemo, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { CalendarDays, CalendarOff, CalendarPlus, Columns3, Download, Filter, LayoutList, Printer, RotateCcw } from 'lucide-react'
import { Link } from 'react-router-dom'
import { lecturesService } from '../../services/lecturesService'
import { lectureOccurrencesService } from '../../services/lectureOccurrencesService'
import { batchesService } from '../../services/batchesService'
import { hallsService } from '../../services/hallsService'
import { instructorsService } from '../../services/instructorsService'
import { useAuth } from '../../context/AuthContext'
import { can } from '../../lib/permissions'
import { usePageTitle } from '../../hooks/usePageTitle'
import { DAY_OPTIONS, formatTime, getDayLabel, getLectureStatus, getStatusLabel, getTodayDbValue, getWeekDates, parseLocalDate, timeToMinutes, toDateKey } from '../../lib/utils'
import { Button } from '../../components/ui/button'
import { Card, CardContent } from '../../components/ui/card'
import { Select } from '../../components/ui/select'
import { Input } from '../../components/ui/input'
import { StatusBadge } from '../../components/common/StatusBadge'
import { LoadingState } from '../../components/common/LoadingState'
import { ErrorState } from '../../components/common/ErrorState'
import { EmptyState } from '../../components/common/EmptyState'
import { LectureOccurrenceAction } from '../../components/lectures/LectureOccurrenceAction'

const VIEWS = [
  { key: 'daily', label: 'اليومي', icon: LayoutList },
  { key: 'weekly', label: 'الأسبوعي', icon: CalendarDays },
  { key: 'hall', label: 'حسب القاعة', icon: Columns3 },
  { key: 'instructor', label: 'حسب المدرس', icon: LayoutList },
  { key: 'batch', label: 'حسب الدفعة', icon: LayoutList },
]
const DAY_START = 7 * 60
const DAY_END = 18 * 60

export function Schedule() {
  usePageTitle('الجدول الأسبوعي')
  const { profile } = useAuth()
  const [view, setView] = useState('weekly')
  const [selectedDate, setSelectedDate] = useState(toDateKey(new Date()))
  const [statusFilter, setStatusFilter] = useState('all')
  const [filters, setFilters] = useState({ hall: '', instructor: '', batch: '', department: '' })
  const selectedDateObject = parseLocalDate(selectedDate)
  const weekDates = useMemo(() => getWeekDates(selectedDateObject), [selectedDate])
  const rangeStart = toDateKey(weekDates[0])
  const rangeEnd = toDateKey(weekDates[6])
  const selectedDay = getTodayDbValue(selectedDateObject)
  const lectures = useQuery({ queryKey: ['schedule'], queryFn: lecturesService.getSchedule })
  const overrides = useQuery({ queryKey: ['lecture-occurrence-overrides', rangeStart, rangeEnd], queryFn: () => lectureOccurrencesService.listForRange(rangeStart, rangeEnd) })
  const halls = useQuery({ queryKey: ['halls', 'schedule'], queryFn: hallsService.list })
  const instructors = useQuery({ queryKey: ['instructors', 'schedule'], queryFn: instructorsService.list })
  const batches = useQuery({ queryKey: ['batches', 'schedule'], queryFn: batchesService.list })
  const overrideKeys = useMemo(() => new Set((overrides.data || []).map((item) => `${item.lecture_id}:${item.occurrence_date}`)), [overrides.data])
  const baseRows = useMemo(() => {
    let data = lectures.data || []
    if (filters.hall) data = data.filter((item) => String(item.hall_id) === String(filters.hall))
    if (filters.instructor) data = data.filter((item) => String(item.instructor_id) === String(filters.instructor))
    if (filters.batch) data = data.filter((item) => String(item.batch_id) === String(filters.batch))
    if (filters.department) data = data.filter((item) => String(item.batch?.department_id) === String(filters.department))
    return data
  }, [lectures.data, filters])
  const makeOccurrence = (lecture, date) => ({ ...lecture, occurrenceDate: toDateKey(date), occurrenceCanceled: Boolean(lecture.canceled || overrideKeys.has(`${lecture.id}:${toDateKey(date)}`)) })
  const getScheduleStatus = (row, date) => {
    if (row.canceled || row.occurrenceCanceled) return 'canceled'
    if (toDateKey(date) !== toDateKey(new Date())) return 'scheduled'
    return getLectureStatus(row, new Date())
  }
  const matchesStatus = (row, date) => {
    const status = getScheduleStatus(row, date)
    if (statusFilter === 'all') return true
    if (statusFilter === 'active') return status !== 'canceled'
    return status === statusFilter
  }
  const selectedRows = useMemo(() => baseRows.filter((row) => row.day_of_week === selectedDay).map((row) => makeOccurrence(row, selectedDateObject)).filter((row) => matchesStatus(row, selectedDateObject)), [baseRows, selectedDay, selectedDate, overrideKeys, statusFilter])
  const weeklyHasRows = useMemo(() => weekDates.some((date) => baseRows.some((row) => row.day_of_week === getTodayDbValue(date) && matchesStatus(makeOccurrence(row, date), date))), [weekDates, baseRows, overrideKeys, statusFilter])
  const departmentOptions = useMemo(() => [...new Map((batches.data || []).map((item) => [item.department_id, item.department]).filter(([id, value]) => id && value)).values()], [batches.data])
  const resetFilters = () => { setSelectedDate(toDateKey(new Date())); setStatusFilter('all'); setFilters({ hall: '', instructor: '', batch: '', department: '' }) }
  const exportRows = view === 'weekly' ? weekDates.flatMap((date) => baseRows.filter((row) => row.day_of_week === getTodayDbValue(date)).map((row) => makeOccurrence(row, date)).filter((row) => matchesStatus(row, date))) : selectedRows
  const exportCsv = () => {
    const headers = ['التاريخ', 'اليوم', 'وقت البداية', 'وقت النهاية', 'المادة', 'المدرس', 'القاعة', 'القسم', 'الدفعة', 'المجموعة', 'الحالة']
    const escape = (value) => `"${String(value ?? '').replaceAll('"', '""')}"`
    const lines = [headers, ...exportRows.map((row) => [row.occurrenceDate, getDayLabel(row.day_of_week), row.start_at, row.end_at, row.subject?.title, row.instructor?.name, row.hall?.title, row.batch?.department?.title || row.batch?.department_abbr, row.batch?.level?.title, row.group, row.occurrenceCanceled ? 'ملغاة لهذا اليوم' : getStatusLabel(getScheduleStatus(row, parseLocalDate(row.occurrenceDate)))])].map((line) => line.map(escape).join(','))
    const blob = new Blob([`\ufeff${lines.join('\n')}`], { type: 'text/csv;charset=utf-8' })
    const url = URL.createObjectURL(blob)
    const anchor = document.createElement('a')
    anchor.href = url
    anchor.download = `university-schedule-${selectedDate}.csv`
    anchor.click()
    URL.revokeObjectURL(url)
  }
  const loading = lectures.isLoading || overrides.isLoading
  const error = lectures.error || overrides.error
  return <div className="page-enter">
    <div className="mb-6 flex flex-col gap-4 lg:flex-row lg:items-end lg:justify-between"><div><p className="eyebrow mb-1.5">التخطيط والتشغيل</p><h1 className="text-2xl font-black tracking-tight sm:text-3xl">الجدول الدراسي</h1><p className="mt-1.5 text-sm leading-7 text-muted-foreground">المحاضرات الأسبوعية هي السلسلة الأساسية، والإلغاء المؤقت يطبق على تاريخ محدد فقط.</p></div><div className="print-hidden flex flex-wrap gap-2"><Button variant="outline" size="sm" onClick={() => window.print()}><Printer className="h-4 w-4" />طباعة / PDF</Button><Button variant="outline" size="sm" onClick={exportCsv} disabled={!exportRows.length}><Download className="h-4 w-4" />تصدير CSV</Button><Link to="/conflicts" className="inline-flex h-9 items-center gap-2 rounded-xl border border-rose-200 bg-rose-50 px-3 text-xs font-bold text-rose-700 hover:bg-rose-100 dark:border-rose-900 dark:bg-rose-950/20 dark:text-rose-300"><CalendarOff className="h-4 w-4" />التعارضات</Link></div></div>
    <div className="print-hidden mb-5 flex flex-wrap gap-2">{VIEWS.map((item) => <Button key={item.key} variant={view === item.key ? 'default' : 'outline'} size="sm" onClick={() => setView(item.key)}><item.icon className="h-4 w-4" />{item.label}</Button>)}</div>
    <Card className="print-hidden mb-5"><CardContent className="flex flex-col gap-3 p-4 xl:flex-row xl:items-center"><div className="flex items-center gap-2 text-sm font-bold"><Filter className="h-4 w-4 text-primary" />الفلاتر</div><Input type="date" value={selectedDate} onChange={(event) => setSelectedDate(event.target.value)} className="h-9 w-full text-xs xl:w-auto xl:min-w-40" /><span className="rounded-lg bg-primary/5 px-3 py-2 text-xs font-bold text-primary">{getDayLabel(selectedDay)}</span><Select value={statusFilter} onChange={(event) => setStatusFilter(event.target.value)} className="h-9 w-full text-xs xl:w-auto xl:min-w-36"><option value="all">كل الحالات</option><option value="active">نشطة</option><option value="canceled">ملغاة</option><option value="scheduled">مجدولة</option><option value="upcoming">قادمة اليوم</option><option value="live">جارية الآن</option><option value="ended">منتهية</option></Select><Select value={filters.department} onChange={(event) => setFilters((current) => ({ ...current, department: event.target.value }))} className="h-9 w-full text-xs xl:w-auto xl:min-w-36"><option value="">كل الأقسام</option>{departmentOptions.map((item) => <option key={item.id} value={item.id}>{item.abbreviation} — {item.title}</option>)}</Select><Select value={filters.hall} onChange={(event) => setFilters((current) => ({ ...current, hall: event.target.value }))} className="h-9 w-full text-xs xl:w-auto xl:min-w-32"><option value="">كل القاعات</option>{(halls.data || []).map((item) => <option key={item.id} value={item.id}>{item.title}</option>)}</Select><Select value={filters.instructor} onChange={(event) => setFilters((current) => ({ ...current, instructor: event.target.value }))} className="h-9 w-full text-xs xl:w-auto xl:min-w-36"><option value="">كل المدرسين</option>{(instructors.data || []).map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}</Select><Select value={filters.batch} onChange={(event) => setFilters((current) => ({ ...current, batch: event.target.value }))} className="h-9 w-full text-xs xl:w-auto xl:min-w-36"><option value="">كل الدفعات</option>{(batches.data || []).map((item) => <option key={item.id} value={item.id}>{item.department_abbr} — {item.level?.title}</option>)}</Select><Button variant="ghost" size="sm" onClick={resetFilters} className="mr-auto"><RotateCcw className="h-4 w-4" />إعادة ضبط</Button></CardContent></Card>
    <div className="print-page-title">الجدول الدراسي — {selectedDate}</div>
    {error ? <ErrorState error={error} onRetry={() => { lectures.refetch(); overrides.refetch() }} /> : loading ? <LoadingState rows={8} /> : view === 'weekly' ? (!weeklyHasRows ? <EmptyState title="لا توجد محاضرات في هذا الأسبوع" description="غيّر التاريخ أو الحالة أو أضف محاضرة من صفحة المحاضرات." /> : <WeeklyTimeline rows={baseRows} weekDates={weekDates} profile={profile} selectedDate={selectedDate} onDateChange={setSelectedDate} overrideKeys={overrideKeys} statusFilter={statusFilter} />) : !selectedRows.length ? <EmptyState title="لا توجد محاضرات في هذا العرض" description="غيّر التاريخ أو الحالة أو الفلاتر، أو أضف محاضرة جديدة." /> : view === 'daily' ? <DailyView rows={selectedRows} profile={profile} /> : <GroupedView rows={selectedRows} mode={view} profile={profile} />}
  </div>
}

function getOccurrenceStatus(lecture, date, overrideKeys, statusFilter) {
  const occurrence = { ...lecture, occurrenceDate: toDateKey(date), occurrenceCanceled: Boolean(lecture.canceled || overrideKeys.has(`${lecture.id}:${toDateKey(date)}`)) }
  const status = occurrence.occurrenceCanceled ? 'canceled' : toDateKey(date) === toDateKey(new Date()) ? getLectureStatus(lecture, new Date()) : 'scheduled'
  if (statusFilter === 'all') return { occurrence, visible: true, status }
  if (statusFilter === 'active') return { occurrence, visible: status !== 'canceled', status }
  return { occurrence, visible: status === statusFilter, status }
}

function WeeklyTimeline({ rows, weekDates, profile, selectedDate, onDateChange, overrideKeys, statusFilter }) {
  const hours = Array.from({ length: Math.floor((DAY_END - DAY_START) / 120) + 1 }, (_, index) => DAY_START + index * 120)
  return <div className="overflow-x-auto rounded-2xl border border-border bg-card shadow-card"><div className="min-w-[1160px]"><div className="grid border-b border-border" style={{ gridTemplateColumns: '64px repeat(7, minmax(150px, 1fr))' }}><div className="p-3" />{weekDates.map((date) => { const day = getTodayDbValue(date); const count = rows.filter((row) => row.day_of_week === day).map((row) => getOccurrenceStatus(row, date, overrideKeys, statusFilter)).filter((result) => result.visible).length; return <button type="button" key={toDateKey(date)} onClick={() => onDateChange(toDateKey(date))} className={`border-r border-border p-3 text-right transition-colors hover:bg-muted/50 ${toDateKey(date) === selectedDate ? 'bg-primary/5' : ''}`}><p className="text-xs font-bold text-muted-foreground">{DAY_OPTIONS[date.getDay()]?.short}</p><p className="mt-1 text-sm font-black">{getDayLabel(day)}</p><p className="mt-1 text-[10px] text-muted-foreground">{date.getDate()} · {count} محاضرات</p></button> })}</div><div className="grid" style={{ gridTemplateColumns: '64px repeat(7, minmax(150px, 1fr))' }}><div className="relative h-[660px] border-l border-border bg-muted/20">{hours.map((hour) => <span key={hour} className="absolute left-2 -translate-y-1/2 font-mono text-[10px] text-muted-foreground" style={{ top: `${((hour - DAY_START) / (DAY_END - DAY_START)) * 100}%` }}>{formatTime(`${String(Math.floor(hour / 60)).padStart(2, '0')}:${String(hour % 60).padStart(2, '0')}`)}</span>)}</div>{weekDates.map((date) => <div key={toDateKey(date)} className={`relative h-[660px] border-r border-border ${toDateKey(date) === selectedDate ? 'bg-primary/[.025]' : ''}`}><TimelineLines hours={hours} />{rows.filter((row) => row.day_of_week === getTodayDbValue(date)).map((row) => { const result = getOccurrenceStatus(row, date, overrideKeys, statusFilter); return result.visible ? <TimelineLecture key={`${row.id}-${toDateKey(date)}`} lecture={result.occurrence} status={result.status} profile={profile} /> : null })}</div>)}</div></div></div>
}

function TimelineLines({ hours }) { return <>{hours.map((hour) => <span key={hour} className="pointer-events-none absolute inset-x-0 h-px bg-border/70" style={{ top: `${((hour - DAY_START) / (DAY_END - DAY_START)) * 100}%` }} />)}</> }

function TimelineLecture({ lecture, status, profile }) {
  const start = timeToMinutes(lecture.start_at)
  const end = timeToMinutes(lecture.end_at)
  const top = Math.max(0, Math.min(100, ((start - DAY_START) / (DAY_END - DAY_START)) * 100))
  const height = Math.max(7, Math.min(100 - top, ((end - start) / (DAY_END - DAY_START)) * 100))
  const target = can(profile, 'lectures.update') ? `/lectures?edit=${lecture.id}` : '/lectures'
  return <div className={`absolute inset-x-1 z-10 overflow-hidden rounded-lg border p-2 text-right shadow-sm transition-all hover:z-20 hover:shadow-md ${lecture.occurrenceCanceled ? 'border-rose-300 bg-rose-50 text-rose-800 dark:border-rose-900 dark:bg-rose-950/35 dark:text-rose-200' : status === 'live' ? 'border-emerald-300 bg-emerald-50 dark:border-emerald-900 dark:bg-emerald-950/35' : 'border-primary/20 bg-primary/5'}`} style={{ top: `${top}%`, height: `${height}%` }}><Link to={target} className="block"><p className="truncate font-mono text-[10px] font-bold">{lecture.start_at?.slice(0, 5)} — {lecture.end_at?.slice(0, 5)}</p><p className="mt-1 line-clamp-2 text-[11px] font-black leading-4">{lecture.subject?.title || 'مادة غير محددة'}</p><p className="mt-1 truncate text-[10px] text-muted-foreground">{lecture.hall?.title || '—'} · {lecture.instructor?.name || '—'}</p>{lecture.occurrenceCanceled && !lecture.canceled ? <p className="mt-1 truncate text-[10px] font-bold text-emerald-700 dark:text-emerald-300">القاعة متاحة لهذا اليوم</p> : null}</Link><div className="mt-1 flex flex-wrap items-center justify-end gap-1"><LectureOccurrenceAction row={lecture} compact /><TemporaryReservationLink lecture={lecture} profile={profile} compact /></div></div>
}

function DailyView({ rows, profile }) {
  const sorted = [...rows].sort((a, b) => a.start_at.localeCompare(b.start_at))
  return <Card><CardContent className="p-5"><div className="mb-5 flex items-center justify-between"><div><p className="text-xs font-bold text-primary">عرض التاريخ المحدد</p><h2 className="mt-1 text-lg font-black">{rows[0]?.occurrenceDate || '—'}</h2></div><p className="text-sm text-muted-foreground">{sorted.length} محاضرات</p></div><div className="relative space-y-3 before:absolute before:bottom-4 before:right-[5.7rem] before:top-4 before:w-px before:bg-border">{sorted.map((row) => <div key={row.id} className="relative flex gap-4"><div className="w-16 shrink-0 pt-3 text-left font-mono text-xs font-bold text-muted-foreground">{row.start_at?.slice(0, 5)}</div><div className="relative z-10 mt-3 h-2.5 w-2.5 shrink-0 rounded-full bg-primary ring-4 ring-primary/10" /><div className="min-w-0 flex-1"><ScheduleCard lecture={row} profile={profile} horizontal /></div></div>)}</div></CardContent></Card>
}

function GroupedView({ rows, mode, profile }) {
  const config = mode === 'hall' ? { key: (row) => row.hall_id, label: (row) => row.hall?.title || 'قاعة غير محددة', sub: (row) => row.hall?.building?.title } : mode === 'instructor' ? { key: (row) => row.instructor_id, label: (row) => row.instructor?.name || 'مدرس غير محدد', sub: (row) => row.instructor?.type } : { key: (row) => row.batch_id, label: (row) => `${row.batch?.department_abbr || ''} — ${row.batch?.level?.title || 'دفعة'}`, sub: (row) => row.batch?.department?.title }
  const groups = [...new Map(rows.map((row) => [config.key(row), { info: row, rows: [] }])).values()]
  rows.forEach((row) => groups.find((group) => config.key(group.info) === config.key(row))?.rows.push(row))
  return <div className="grid gap-4 lg:grid-cols-2">{groups.map((group) => <Card key={config.key(group.info)}><CardContent className="p-5"><div className="mb-4 flex items-start justify-between border-b border-border pb-4"><div><h2 className="font-black">{config.label(group.info)}</h2><p className="mt-1 text-xs text-muted-foreground">{config.sub(group.info)}</p></div><span className="rounded-full bg-primary/10 px-2.5 py-1 text-xs font-bold text-primary">{group.rows.length} محاضرات</span></div><div className="space-y-2">{group.rows.sort((a, b) => a.start_at.localeCompare(b.start_at)).map((row) => <ScheduleCard key={row.id} lecture={row} profile={profile} horizontal />)}</div></CardContent></Card>)}</div>
}

function ScheduleCard({ lecture, profile, horizontal = false }) {
  const status = lecture.occurrenceCanceled ? 'canceled' : lecture.day_of_week === getTodayDbValue(new Date()) ? getLectureStatus(lecture) : 'scheduled'
  const target = can(profile, 'lectures.update') ? `/lectures?edit=${lecture.id}` : '/lectures'
  return <div className={`rounded-xl border border-border p-3 transition-colors hover:border-primary/40 hover:shadow-sm ${lecture.occurrenceCanceled ? 'bg-rose-500/[.035]' : 'bg-muted/30'} ${horizontal ? 'flex flex-wrap items-center gap-3' : ''}`}><Link to={target} className={horizontal ? 'min-w-32' : 'block'}><div className="flex items-center justify-between gap-2"><span className="font-mono text-[11px] font-bold text-primary">{lecture.start_at?.slice(0, 5)} — {lecture.end_at?.slice(0, 5)}</span>{!horizontal ? <StatusBadge status={status} label={lecture.occurrenceCanceled ? 'ملغاة لهذا اليوم' : undefined} /> : null}</div><p className="mt-2 line-clamp-2 text-xs font-black leading-5">{lecture.subject?.title || 'مادة غير محددة'}</p></Link>{horizontal ? <div className="flex flex-1 flex-wrap items-center gap-x-4 gap-y-1 text-xs text-muted-foreground"><span>قاعة {lecture.hall?.title || '—'}</span><span>{lecture.instructor?.name || '—'}</span><span>{lecture.batch?.department_abbr} — {lecture.batch?.level?.title}</span></div> : <div className="mt-2 space-y-1 text-[11px] text-muted-foreground"><p>{lecture.hall?.title || '—'} · {lecture.instructor?.name || '—'}</p><p>{lecture.batch?.department_abbr} — {lecture.batch?.level?.title}</p></div>}{lecture.occurrenceCanceled && !lecture.canceled ? <p className="mt-2 rounded-lg bg-emerald-500/10 px-2 py-1.5 text-[11px] font-bold text-emerald-700 dark:text-emerald-300">تم تحرير القاعة لهذا التاريخ فقط</p> : null}{horizontal ? <><StatusBadge status={status} label={lecture.occurrenceCanceled ? 'ملغاة لهذا اليوم' : undefined} /><LectureOccurrenceAction row={lecture} compact /><TemporaryReservationLink lecture={lecture} profile={profile} compact /></> : <div className="mt-2 flex flex-wrap justify-end gap-1"><LectureOccurrenceAction row={lecture} compact /><TemporaryReservationLink lecture={lecture} profile={profile} /></div>}</div>
}

function TemporaryReservationLink({ lecture, profile, compact = false }) {
  if (!lecture?.occurrenceDate || lecture.canceled || !lecture.occurrenceCanceled || !can(profile, 'hall_reservations.create')) return null
  const params = new URLSearchParams({ mode: 'date', hall_id: String(lecture.hall_id), reservation_date: lecture.occurrenceDate, start_at: lecture.start_at?.slice(0, 5) || '', end_at: lecture.end_at?.slice(0, 5) || '' })
  if (lecture.batch?.department_id) params.set('department_id', String(lecture.batch.department_id))
  if (lecture.batch?.level_id) params.set('level_id', String(lecture.batch.level_id))
  return <Link to={`/reservations?${params.toString()}`} onClick={(event) => event.stopPropagation()} className={`inline-flex items-center gap-1 rounded-lg font-bold text-emerald-700 transition-colors hover:bg-emerald-500/10 dark:text-emerald-300 ${compact ? 'h-7 w-7 justify-center text-[0px]' : 'px-2 py-1 text-[11px]'}`} title="إنشاء حجز مؤقت لهذا التاريخ"><CalendarPlus className="h-3.5 w-3.5" />{compact ? null : 'حجز القاعة لهذا اليوم'}</Link>
}
