import { useMemo, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { CalendarDays, Columns3, Download, Filter, LayoutList, Printer, RotateCcw } from 'lucide-react'
import { Link } from 'react-router-dom'
import { lecturesService } from '../../services/lecturesService'
import { batchesService } from '../../services/batchesService'
import { hallsService } from '../../services/hallsService'
import { instructorsService } from '../../services/instructorsService'
import { useAuth } from '../../context/AuthContext'
import { can } from '../../lib/permissions'
import { usePageTitle } from '../../hooks/usePageTitle'
import { DAY_OPTIONS, formatTime, getDayLabel, getLectureStatus, getStatusLabel, timeToMinutes } from '../../lib/utils'
import { Button } from '../../components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '../../components/ui/card'
import { Select } from '../../components/ui/select'
import { StatusBadge } from '../../components/common/StatusBadge'
import { LoadingState } from '../../components/common/LoadingState'
import { ErrorState } from '../../components/common/ErrorState'
import { EmptyState } from '../../components/common/EmptyState'

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
  const [day, setDay] = useState(DAY_OPTIONS[new Date().getDay()]?.value || 'احد')
  const [statusFilter, setStatusFilter] = useState('all')
  const [filters, setFilters] = useState({ hall: '', instructor: '', batch: '', department: '' })
  const lectures = useQuery({ queryKey: ['schedule'], queryFn: lecturesService.getSchedule })
  const halls = useQuery({ queryKey: ['halls', 'schedule'], queryFn: hallsService.list })
  const instructors = useQuery({ queryKey: ['instructors', 'schedule'], queryFn: instructorsService.list })
  const batches = useQuery({ queryKey: ['batches', 'schedule'], queryFn: batchesService.list })

  const rows = useMemo(() => {
    let data = lectures.data || []
    if (filters.hall) data = data.filter((item) => String(item.hall_id) === String(filters.hall))
    if (filters.instructor) data = data.filter((item) => String(item.instructor_id) === String(filters.instructor))
    if (filters.batch) data = data.filter((item) => String(item.batch_id) === String(filters.batch))
    if (filters.department) data = data.filter((item) => String(item.batch?.department_id) === String(filters.department))
    if (statusFilter !== 'all') {
      data = data.filter((item) => {
        if (statusFilter === 'active') return !item.canceled
        if (statusFilter === 'canceled') return item.canceled
        return !item.canceled && getLectureStatus(item) === statusFilter
      })
    }
    return data
  }, [lectures.data, filters, statusFilter])

  const displayRows = view === 'weekly' ? rows : rows.filter((item) => !day || item.day_of_week === day)
  const departmentOptions = useMemo(() => [...new Map((batches.data || []).map((item) => [item.department_id, item.department]).filter(([id, value]) => id && value)).values()], [batches.data])
  const resetFilters = () => {
    setDay('')
    setStatusFilter('all')
    setFilters({ hall: '', instructor: '', batch: '', department: '' })
  }

  const exportCsv = () => {
    const headers = ['اليوم', 'وقت البداية', 'وقت النهاية', 'المادة', 'المدرس', 'القاعة', 'القسم', 'الدفعة', 'المجموعة', 'الحالة']
    const escape = (value) => `"${String(value ?? '').replaceAll('"', '""')}"`
    const lines = [headers, ...displayRows.map((row) => [
      getDayLabel(row.day_of_week), row.start_at, row.end_at, row.subject?.title, row.instructor?.name,
      row.hall?.title, row.batch?.department?.title || row.batch?.department_abbr,
      row.batch?.level?.title, row.group, row.canceled ? 'ملغاة' : getStatusLabel(getLectureStatus(row)),
    ])].map((line) => line.map(escape).join(','))
    const blob = new Blob([`\ufeff${lines.join('\n')}`], { type: 'text/csv;charset=utf-8' })
    const url = URL.createObjectURL(blob)
    const anchor = document.createElement('a')
    anchor.href = url
    anchor.download = `university-schedule-${new Date().toISOString().slice(0, 10)}.csv`
    anchor.click()
    URL.revokeObjectURL(url)
  }

  return <div className="page-enter">
    <div className="mb-6 flex flex-col gap-4 lg:flex-row lg:items-end lg:justify-between">
      <div><p className="mb-1 text-xs font-bold uppercase tracking-[.16em] text-primary">التخطيط والتشغيل</p><h1 className="text-2xl font-black tracking-tight sm:text-3xl">الجدول الدراسي</h1><p className="mt-1 text-sm leading-6 text-muted-foreground">استعرض الجدول زمنيًا أو يوميًا وبحسب القاعة والمدرس والدفعة.</p></div>
      <div className="print-hidden flex flex-wrap gap-2"><Button variant="outline" size="sm" onClick={() => window.print()}><Printer className="h-4 w-4" />طباعة / PDF</Button><Button variant="outline" size="sm" onClick={exportCsv} disabled={!displayRows.length}><Download className="h-4 w-4" />تصدير CSV</Button></div>
    </div>
    <div className="print-hidden mb-5 flex flex-wrap gap-2">{VIEWS.map((item) => <Button key={item.key} variant={view === item.key ? 'default' : 'outline'} size="sm" onClick={() => setView(item.key)}><item.icon className="h-4 w-4" />{item.label}</Button>)}</div>
    <Card className="print-hidden mb-5"><CardContent className="flex flex-col gap-3 p-4 xl:flex-row xl:items-center"><div className="flex items-center gap-2 text-sm font-bold"><Filter className="h-4 w-4 text-primary" />الفلاتر</div><Select value={day} onChange={(event) => setDay(event.target.value)} className="h-9 w-full text-xs xl:w-auto xl:min-w-32"><option value="">كل الأيام</option>{DAY_OPTIONS.map((item) => <option key={item.value} value={item.value}>{item.label}</option>)}</Select><Select value={statusFilter} onChange={(event) => setStatusFilter(event.target.value)} className="h-9 w-full text-xs xl:w-auto xl:min-w-36"><option value="all">كل الحالات</option><option value="active">نشطة</option><option value="canceled">ملغاة</option><option value="live">جارية الآن</option><option value="upcoming">قادمة</option><option value="ended">منتهية</option></Select><Select value={filters.department} onChange={(event) => setFilters((current) => ({ ...current, department: event.target.value }))} className="h-9 w-full text-xs xl:w-auto xl:min-w-36"><option value="">كل الأقسام</option>{departmentOptions.map((item) => <option key={item.id} value={item.id}>{item.abbreviation} — {item.title}</option>)}</Select><Select value={filters.hall} onChange={(event) => setFilters((current) => ({ ...current, hall: event.target.value }))} className="h-9 w-full text-xs xl:w-auto xl:min-w-32"><option value="">كل القاعات</option>{(halls.data || []).map((item) => <option key={item.id} value={item.id}>{item.title}</option>)}</Select><Select value={filters.instructor} onChange={(event) => setFilters((current) => ({ ...current, instructor: event.target.value }))} className="h-9 w-full text-xs xl:w-auto xl:min-w-36"><option value="">كل المدرسين</option>{(instructors.data || []).map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}</Select><Select value={filters.batch} onChange={(event) => setFilters((current) => ({ ...current, batch: event.target.value }))} className="h-9 w-full text-xs xl:w-auto xl:min-w-36"><option value="">كل الدفعات</option>{(batches.data || []).map((item) => <option key={item.id} value={item.id}>{item.department_abbr} — {item.level?.title}</option>)}</Select><Button variant="ghost" size="sm" onClick={resetFilters} className="mr-auto"><RotateCcw className="h-4 w-4" />إعادة ضبط</Button></CardContent></Card>
    {lectures.isError ? <ErrorState error={lectures.error} onRetry={() => lectures.refetch()} /> : lectures.isLoading ? <LoadingState rows={8} /> : !displayRows.length ? <EmptyState title="لا توجد محاضرات في هذا العرض" description="غيّر اليوم أو الحالة أو الفلاتر، أو أضف محاضرة جديدة من صفحة المحاضرات." /> : view === 'weekly' ? <WeeklyTimeline rows={rows} profile={profile} selectedDay={day} onDayChange={setDay} /> : view === 'daily' ? <DailyView rows={displayRows} day={day} profile={profile} /> : <GroupedView rows={displayRows} mode={view} profile={profile} />}
  </div>
}

function WeeklyTimeline({ rows, profile, selectedDay, onDayChange }) {
  const hours = Array.from({ length: Math.floor((DAY_END - DAY_START) / 120) + 1 }, (_, index) => DAY_START + index * 120)
  return <div className="overflow-x-auto rounded-2xl border border-border bg-card shadow-card"><div className="min-w-[1160px]"><div className="grid border-b border-border" style={{ gridTemplateColumns: '64px repeat(7, minmax(150px, 1fr))' }}><div className="p-3" />{DAY_OPTIONS.map((day) => { const count = rows.filter((row) => row.day_of_week === day.value).length; return <button type="button" key={day.value} onClick={() => onDayChange(day.value)} className={`border-r border-border p-3 text-right transition-colors hover:bg-muted/50 ${selectedDay === day.value ? 'bg-primary/5' : ''}`}><p className="text-xs font-bold text-muted-foreground">{day.short}</p><p className="mt-1 text-sm font-black">{day.label}</p><p className="mt-1 text-[10px] text-muted-foreground">{count} محاضرات</p></button> })}</div><div className="grid" style={{ gridTemplateColumns: '64px repeat(7, minmax(150px, 1fr))' }}><div className="relative h-[660px] border-l border-border bg-muted/20">{hours.map((hour) => <span key={hour} className="absolute left-2 -translate-y-1/2 font-mono text-[10px] text-muted-foreground" style={{ top: `${((hour - DAY_START) / (DAY_END - DAY_START)) * 100}%` }}>{formatTime(`${String(Math.floor(hour / 60)).padStart(2, '0')}:${String(hour % 60).padStart(2, '0')}`)}</span>)}</div>{DAY_OPTIONS.map((day) => <div key={day.value} className={`relative h-[660px] border-r border-border ${selectedDay === day.value ? 'bg-primary/[.025]' : ''}`}><TimelineLines hours={hours} />{rows.filter((row) => row.day_of_week === day.value).map((row) => <TimelineLecture key={row.id} lecture={row} profile={profile} />)}</div>)}</div></div></div>
}

function TimelineLines({ hours }) { return <>{hours.map((hour) => <span key={hour} className="pointer-events-none absolute inset-x-0 h-px bg-border/70" style={{ top: `${((hour - DAY_START) / (DAY_END - DAY_START)) * 100}%` }} />)}</> }

function TimelineLecture({ lecture, profile }) {
  const start = timeToMinutes(lecture.start_at)
  const end = timeToMinutes(lecture.end_at)
  const top = Math.max(0, Math.min(100, ((start - DAY_START) / (DAY_END - DAY_START)) * 100))
  const height = Math.max(7, Math.min(100 - top, ((end - start) / (DAY_END - DAY_START)) * 100))
  const status = lecture.canceled ? 'canceled' : getLectureStatus(lecture)
  const target = can(profile, 'lectures.update') ? `/lectures?edit=${lecture.id}` : '/lectures'
  return <Link to={target} className={`absolute inset-x-1 z-10 overflow-hidden rounded-lg border p-2 text-right shadow-sm transition-all hover:z-20 hover:shadow-md ${lecture.canceled ? 'border-rose-300 bg-rose-50 text-rose-800 dark:border-rose-900 dark:bg-rose-950/35 dark:text-rose-200' : status === 'live' ? 'border-emerald-300 bg-emerald-50 dark:border-emerald-900 dark:bg-emerald-950/35' : 'border-primary/20 bg-primary/5'}`} style={{ top: `${top}%`, height: `${height}%` }}><p className="truncate font-mono text-[10px] font-bold">{lecture.start_at?.slice(0, 5)} — {lecture.end_at?.slice(0, 5)}</p><p className="mt-1 line-clamp-2 text-[11px] font-black leading-4">{lecture.subject?.title || 'مادة غير محددة'}</p><p className="mt-1 truncate text-[10px] text-muted-foreground">{lecture.hall?.title || '—'} · {lecture.instructor?.name || '—'}</p></Link>
}

function DailyView({ rows, day, profile }) {
  const sorted = [...rows].sort((a, b) => a.start_at.localeCompare(b.start_at))
  return <Card><CardContent className="p-5"><div className="mb-5 flex items-center justify-between"><div><p className="text-xs font-bold text-primary">عرض اليوم</p><h2 className="mt-1 text-lg font-black">{day ? getDayLabel(day) : 'كل الأيام'}</h2></div><p className="text-sm text-muted-foreground">{sorted.length} محاضرات</p></div><div className="relative space-y-3 before:absolute before:bottom-4 before:right-[5.7rem] before:top-4 before:w-px before:bg-border">{sorted.map((row) => <div key={row.id} className="relative flex gap-4"><div className="w-16 shrink-0 pt-3 text-left font-mono text-xs font-bold text-muted-foreground">{row.start_at?.slice(0, 5)}</div><div className="relative z-10 mt-3 h-2.5 w-2.5 shrink-0 rounded-full bg-primary ring-4 ring-primary/10" /><div className="min-w-0 flex-1"><ScheduleCard lecture={row} profile={profile} horizontal /></div></div>)}</div></CardContent></Card>
}

function GroupedView({ rows, mode, profile }) {
  const config = mode === 'hall' ? { key: (row) => row.hall_id, label: (row) => row.hall?.title || 'قاعة غير محددة', sub: (row) => row.hall?.building?.title } : mode === 'instructor' ? { key: (row) => row.instructor_id, label: (row) => row.instructor?.name || 'مدرس غير محدد', sub: (row) => row.instructor?.type } : { key: (row) => row.batch_id, label: (row) => `${row.batch?.department_abbr || ''} — ${row.batch?.level?.title || 'دفعة'}`, sub: (row) => row.batch?.department?.title }
  const groups = [...new Map(rows.map((row) => [config.key(row), { info: row, rows: [] }])).values()]
  rows.forEach((row) => groups.find((group) => config.key(group.info) === config.key(row))?.rows.push(row))
  return <div className="grid gap-4 lg:grid-cols-2">{groups.map((group) => <Card key={config.key(group.info)}><CardContent className="p-5"><div className="mb-4 flex items-start justify-between border-b border-border pb-4"><div><h2 className="font-black">{config.label(group.info)}</h2><p className="mt-1 text-xs text-muted-foreground">{config.sub(group.info)}</p></div><span className="rounded-full bg-primary/10 px-2.5 py-1 text-xs font-bold text-primary">{group.rows.length} محاضرات</span></div><div className="space-y-2">{group.rows.sort((a, b) => a.day_of_week.localeCompare(b.day_of_week) || a.start_at.localeCompare(b.start_at)).map((row) => <ScheduleCard key={row.id} lecture={row} profile={profile} horizontal />)}</div></CardContent></Card>)}</div>
}

function ScheduleCard({ lecture, profile, horizontal = false }) {
  const status = lecture.canceled ? 'canceled' : getLectureStatus(lecture)
  const target = can(profile, 'lectures.update') ? `/lectures?edit=${lecture.id}` : '/lectures'
  return <Link to={target} className={`block rounded-xl border border-border p-3 transition-colors hover:border-primary/40 hover:shadow-sm ${lecture.canceled ? 'bg-rose-500/[.035]' : 'bg-muted/30'} ${horizontal ? 'flex flex-wrap items-center gap-3' : ''}`}><div className={horizontal ? 'min-w-32' : ''}><div className="flex items-center justify-between gap-2"><span className="font-mono text-[11px] font-bold text-primary">{lecture.start_at?.slice(0, 5)} — {lecture.end_at?.slice(0, 5)}</span>{!horizontal ? <StatusBadge status={status} label={lecture.canceled ? 'ملغاة' : undefined} /> : null}</div><p className="mt-2 line-clamp-2 text-xs font-black leading-5">{lecture.subject?.title || 'مادة غير محددة'}</p></div>{horizontal ? <div className="flex flex-1 flex-wrap items-center gap-x-4 gap-y-1 text-xs text-muted-foreground"><span>قاعة {lecture.hall?.title || '—'}</span><span>{lecture.instructor?.name || '—'}</span><span>{lecture.batch?.department_abbr} — {lecture.batch?.level?.title}</span></div> : <div className="mt-2 space-y-1 text-[11px] text-muted-foreground"><p>{lecture.hall?.title || '—'} · {lecture.instructor?.name || '—'}</p><p>{lecture.batch?.department_abbr} — {lecture.batch?.level?.title}</p></div>}{horizontal ? <StatusBadge status={status} label={lecture.canceled ? 'ملغاة' : undefined} /> : null}</Link>
}
