import { useEffect, useMemo, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Check, Layers3, Save } from 'lucide-react'
import { toast } from 'sonner'
import { useAuth } from '../../context/AuthContext'
import { can } from '../../lib/permissions'
import { usePageTitle } from '../../hooks/usePageTitle'
import { departmentsService } from '../../services/departmentsService'
import { levelsService } from '../../services/levelsService'
import { departmentLevelsService } from '../../services/departmentLevelsService'
import { Button } from '../../components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '../../components/ui/card'
import { Select } from '../../components/ui/select'
import { Badge } from '../../components/ui/badge'
import { ErrorState } from '../../components/common/ErrorState'
import { LoadingState } from '../../components/common/LoadingState'

export function DepartmentLevels() {
  usePageTitle('ربط الأقسام بالمستويات')
  const { profile } = useAuth()
  const queryClient = useQueryClient()
  const [departmentId, setDepartmentId] = useState('')
  const [selectedLevels, setSelectedLevels] = useState([])
  const departments = useQuery({ queryKey: ['departments', 'department-levels'], queryFn: departmentsService.list, enabled: can(profile, 'departments.update') })
  const levels = useQuery({ queryKey: ['levels', 'department-levels'], queryFn: levelsService.list, enabled: can(profile, 'departments.update') })
  const mappings = useQuery({ queryKey: ['department-levels'], queryFn: departmentLevelsService.list, enabled: can(profile, 'departments.update') })
  const availableDepartments = departments.data || []
  const availableLevels = levels.data || []
  useEffect(() => {
    if (!departmentId && availableDepartments[0]) setDepartmentId(String(availableDepartments[0].id))
  }, [availableDepartments, departmentId])
  const mappedIds = useMemo(() => new Set((mappings.data || []).filter((item) => String(item.department_id) === String(departmentId)).map((item) => String(item.level_id))), [mappings.data, departmentId])
  useEffect(() => { setSelectedLevels([...mappedIds]) }, [departmentId, mappings.data])
  const mutation = useMutation({ mutationFn: () => departmentLevelsService.set(departmentId, selectedLevels), onSuccess: () => { queryClient.invalidateQueries({ queryKey: ['department-levels'] }); queryClient.invalidateQueries({ queryKey: ['users'] }); queryClient.invalidateQueries({ queryKey: ['batches'] }); queryClient.invalidateQueries({ queryKey: ['lectures'] }); toast.success('تم حفظ ربط القسم بالمستويات') }, onError: (error) => toast.error(error.message || 'تعذر حفظ الربط') })
  if (!can(profile, 'departments.update')) return <ErrorState title="لا تملك صلاحية الوصول" error="إدارة ربط الأقسام بالمستويات متاحة للإدارة الأكاديمية فقط." />
  if (departments.isLoading || levels.isLoading || mappings.isLoading) return <LoadingState rows={6} />
  if (departments.isError || levels.isError || mappings.isError) return <ErrorState error={departments.error || levels.error || mappings.error} onRetry={() => { departments.refetch(); levels.refetch(); mappings.refetch() }} />
  const toggle = (levelId) => setSelectedLevels((current) => current.includes(String(levelId)) ? current.filter((id) => id !== String(levelId)) : [...current, String(levelId)])
  const department = availableDepartments.find((item) => String(item.id) === String(departmentId))
  return <div className="page-enter"><div className="mb-6"><p className="eyebrow mb-1.5">الإدارة الأكاديمية</p><h1 className="text-2xl font-black tracking-tight sm:text-3xl">ربط الأقسام بالمستويات</h1><p className="mt-1.5 max-w-2xl text-sm leading-7 text-muted-foreground">عرّف المستويات التابعة لكل قسم قبل تعيين نطاقات مديري الأقسام. هذا الربط يمنع اختيار مستوى غير تابع للقسم.</p></div><div className="grid gap-5 lg:grid-cols-[320px_1fr]"><Card className="h-fit"><CardHeader><CardTitle>القسم</CardTitle></CardHeader><CardContent><Select value={departmentId} onChange={(event) => setDepartmentId(event.target.value)}><option value="">اختر القسم</option>{availableDepartments.map((item) => <option key={item.id} value={item.id}>{item.abbreviation} — {item.title}</option>)}</Select>{department ? <div className="mt-4 rounded-xl bg-muted/50 p-3 text-xs leading-6 text-muted-foreground">عدد المستويات المسجل في القسم: <strong className="text-foreground">{department.num_levels}</strong><br />المستويات المحددة حاليًا: <strong className="text-foreground">{selectedLevels.length}</strong></div> : null}</CardContent></Card><Card><CardHeader className="flex-row items-center justify-between"><div><CardTitle className="flex items-center gap-2"><Layers3 className="h-5 w-5 text-primary" />المستويات التابعة</CardTitle><p className="mt-1 text-xs text-muted-foreground">يمكن اختيار أكثر أو أقل من العدد المقترح، لكن لن يستطيع مدير القسم تجاوز الربط المحفوظ.</p></div><Badge variant="outline">{selectedLevels.length} محدد</Badge></CardHeader><CardContent><div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">{availableLevels.map((level) => { const checked = selectedLevels.includes(String(level.id)); return <button type="button" key={level.id} onClick={() => toggle(level.id)} className={`flex items-center justify-between rounded-xl border p-4 text-right transition-all ${checked ? 'border-primary bg-primary/5 shadow-sm' : 'border-border hover:border-primary/40 hover:bg-muted/40'}`}><span><span className="block text-sm font-black">{level.title}</span><span className="mt-1 block text-[11px] text-muted-foreground">Level #{level.id}</span></span><span className={`flex h-7 w-7 items-center justify-center rounded-lg ${checked ? 'bg-primary text-primary-foreground' : 'bg-muted text-muted-foreground'}`}>{checked ? <Check className="h-4 w-4" /> : null}</span></button> })}</div><div className="mt-5 flex justify-start"><Button onClick={() => mutation.mutate()} disabled={!departmentId || mutation.isPending}><Save className="h-4 w-4" />{mutation.isPending ? 'جارٍ الحفظ…' : 'حفظ الربط'}</Button></div></CardContent></Card></div></div>
}
