import { useMemo, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { CalendarClock, DoorOpen, GraduationCap, RefreshCw, TriangleAlert, UserRound } from 'lucide-react'
import { Link } from 'react-router-dom'
import { conflictsService } from '../../services/conflictsService'
import { lecturesService } from '../../services/lecturesService'
import { useAuth } from '../../context/AuthContext'
import { can } from '../../lib/permissions'
import { formatGroups, getDayLabel, formatTime } from '../../lib/utils'
import { usePageTitle } from '../../hooks/usePageTitle'
import { Button } from '../../components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '../../components/ui/card'
import { Badge } from '../../components/ui/badge'
import { PageHeader } from '../../components/common/PageHeader'
import { EmptyState } from '../../components/common/EmptyState'
import { ErrorState } from '../../components/common/ErrorState'
import { LoadingState } from '../../components/common/LoadingState'
import { LectureLifecycleAction } from '../../components/lectures/LectureLifecycleAction'

const conflictTypes = {
  hall: { label: 'تعارض قاعة', icon: DoorOpen, tone: 'danger' },
  instructor: { label: 'تعارض مدرس', icon: UserRound, tone: 'warning' },
  batch: { label: 'تعارض دفعة', icon: GraduationCap, tone: 'info' },
}

export function ConflictCenter() {
  usePageTitle('مركز التعارضات')
  const { profile } = useAuth()
  const [typeFilter, setTypeFilter] = useState('all')
  const conflicts = useQuery({ queryKey: ['conflicts'], queryFn: conflictsService.list })
  const lectures = useQuery({ queryKey: ['lectures', 'conflict-center'], queryFn: lecturesService.list })
  const lectureMap = useMemo(() => new Map((lectures.data || []).map((lecture) => [String(lecture.id), lecture])), [lectures.data])
  const visibleConflicts = useMemo(() => (conflicts.data || []).filter((item) => typeFilter === 'all' || item.conflict_type === typeFilter), [conflicts.data, typeFilter])
  const totals = useMemo(() => (conflicts.data || []).reduce((acc, item) => ({ ...acc, [item.conflict_type]: (acc[item.conflict_type] || 0) + 1 }), {}), [conflicts.data])
  const isLoading = conflicts.isLoading || lectures.isLoading
  const isError = conflicts.isError || lectures.isError
  const retry = () => { conflicts.refetch(); lectures.refetch() }
  return <div className="page-enter"><PageHeader title="مركز التعارضات" description="اكتشف تعارضات الجدول الحالية واعالجها بتعديل إحدى المحاضرات أو إلغائها، دون حذف أي سجل." icon={TriangleAlert}><Button variant="outline" onClick={retry} disabled={isLoading}><RefreshCw className="h-4 w-4" />تحديث</Button></PageHeader>{isError ? <ErrorState error={conflicts.error || lectures.error} onRetry={retry} /> : isLoading ? <LoadingState rows={6} /> : <><div className="mb-5 grid gap-3 sm:grid-cols-2 xl:grid-cols-4"><SummaryCard label="إجمالي التعارضات" value={(conflicts.data || []).length} icon={TriangleAlert} tone="bg-rose-500/10 text-rose-600" /><SummaryCard label="تعارضات القاعات" value={totals.hall || 0} icon={DoorOpen} tone="bg-amber-500/10 text-amber-600" /><SummaryCard label="تعارضات المدرسين" value={totals.instructor || 0} icon={UserRound} tone="bg-blue-500/10 text-blue-600" /><SummaryCard label="تعارضات الدفعات" value={totals.batch || 0} icon={GraduationCap} tone="bg-violet-500/10 text-violet-600" /></div><Card className="overflow-hidden"><CardHeader className="flex-col gap-3 border-b border-border sm:flex-row sm:items-center sm:justify-between"><div><CardTitle>التعارضات الحالية</CardTitle><p className="mt-1 text-xs text-muted-foreground">المحاضرات الملغاة مستبعدة من هذا التقرير.</p></div><div className="flex flex-wrap gap-2"><FilterButton active={typeFilter === 'all'} onClick={() => setTypeFilter('all')}>الكل ({(conflicts.data || []).length})</FilterButton>{Object.entries(conflictTypes).map(([key, item]) => <FilterButton key={key} active={typeFilter === key} onClick={() => setTypeFilter(key)}>{item.label} ({totals[key] || 0})</FilterButton>)}</div></CardHeader><CardContent className="p-4">{visibleConflicts.length ? <div className="grid gap-4 lg:grid-cols-2">{visibleConflicts.map((conflict, index) => <ConflictCard key={`${conflict.conflict_type}-${conflict.lecture_a_id}-${conflict.lecture_b_id}-${index}`} conflict={conflict} first={lectureMap.get(String(conflict.lecture_a_id))} second={lectureMap.get(String(conflict.lecture_b_id))} profile={profile} />)}</div> : <EmptyState title="لا توجد تعارضات" description="الجدول الحالي لا يحتوي على تعارضات نشطة ضمن نطاق صلاحيتك." />}</CardContent></Card></>}</div>
}

function ConflictCard({ conflict, first, second, profile }) {
  const config = conflictTypes[conflict.conflict_type] || conflictTypes.hall
  const Icon = config.icon
  const resourceLabel = conflict.conflict_type === 'hall' ? `القاعة ${first?.hall?.title || `#${conflict.resource_id}`}` : conflict.conflict_type === 'instructor' ? (first?.instructor?.name || `المدرس #${conflict.resource_id}`) : `${first?.batch?.department_abbr || ''} — ${first?.batch?.level?.title || `الدفعة #${conflict.resource_id}`}`
  return <div className="rounded-2xl border border-rose-200 bg-rose-50/40 p-4 dark:border-rose-900/50 dark:bg-rose-950/10"><div className="flex items-start justify-between gap-3"><div className="flex items-start gap-3"><div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-rose-500/10 text-rose-600"><Icon className="h-5 w-5" /></div><div><div className="flex flex-wrap items-center gap-2"><Badge variant={config.tone}>{config.label}</Badge><span className="text-xs font-bold">{resourceLabel}</span></div><p className="mt-2 flex items-center gap-1.5 text-xs font-semibold text-muted-foreground"><CalendarClock className="h-3.5 w-3.5" />{getDayLabel(conflict.day_of_week)} · {formatTime(conflict.overlap_start)} — {formatTime(conflict.overlap_end)}</p></div></div></div><div className="mt-4 grid gap-2 sm:grid-cols-2"><LectureMiniCard lecture={first} id={conflict.lecture_a_id} profile={profile} /><LectureMiniCard lecture={second} id={conflict.lecture_b_id} profile={profile} /></div><div className="mt-4 flex flex-wrap items-center gap-2 border-t border-rose-200/80 pt-3 dark:border-rose-900/50"><span className="ml-auto text-[11px] text-muted-foreground">الحل: عدّل القاعة أو الوقت أو ألغِ إحدى المحاضرتين.</span>{first && can(profile, 'lectures.cancel_series') ? <LectureLifecycleAction row={first} /> : null}{second && can(profile, 'lectures.cancel_series') ? <LectureLifecycleAction row={second} /> : null}</div></div>
}

function LectureMiniCard({ lecture, id, profile }) {
  if (!lecture) return <div className="rounded-xl border border-dashed border-border p-3 text-xs text-muted-foreground">المحاضرة #{id} غير ظاهرة ضمن نطاق القراءة.</div>
  const canEdit = can(profile, 'lectures.update')
  return <div className="rounded-xl border border-border bg-card p-3"><p className="truncate text-sm font-black">{lecture.subject?.title || 'مادة غير محددة'}</p><p className="mt-1 text-xs text-muted-foreground">{lecture.instructor?.name || '—'} · قاعة {lecture.hall?.title || '—'}</p><p className="mt-1 text-xs text-muted-foreground">{lecture.batch?.department_abbr} — {lecture.batch?.level?.title}</p><p className="mt-1 text-xs font-semibold text-primary">المجموعات: {formatGroups(lecture.groups)}</p>{canEdit ? <Link to={`/lectures?edit=${lecture.id}`} className="mt-3 inline-flex text-xs font-bold text-primary hover:underline">فتح المحاضرة للتعديل ←</Link> : <span className="mt-3 block text-[11px] text-muted-foreground">المحاضرة #{lecture.id}</span>}</div>
}

function FilterButton({ active, children, onClick }) { return <Button variant={active ? 'secondary' : 'ghost'} size="sm" className="h-8 text-xs" onClick={onClick}>{children}</Button> }
function SummaryCard({ label, value, icon: Icon, tone }) { return <Card><CardContent className="flex items-center justify-between p-4"><div><p className="text-xs font-bold text-muted-foreground">{label}</p><p className="mt-1 text-2xl font-black">{value}</p></div><div className={`flex h-10 w-10 items-center justify-center rounded-xl ${tone}`}><Icon className="h-5 w-5" /></div></CardContent></Card> }
