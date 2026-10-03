import { useMemo, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Building2, Layers3, UserCheck, UserPlus, UserRound, UserX, Users as UsersIcon } from 'lucide-react'
import { z } from 'zod'
import { toast } from 'sonner'
import { usersService } from '../../services/usersService'
import { departmentsService } from '../../services/departmentsService'
import { levelsService } from '../../services/levelsService'
import { departmentLevelsService } from '../../services/departmentLevelsService'
import { ROLE_LABELS, ROLE_KEYS, can, getRoleLabel } from '../../lib/permissions'
import { useAuth } from '../../context/AuthContext'
import { usePageTitle } from '../../hooks/usePageTitle'
import { getInitials, getErrorMessage } from '../../lib/utils'
import { Button } from '../../components/ui/button'
import { Card } from '../../components/ui/card'
import { Input } from '../../components/ui/input'
import { Select } from '../../components/ui/select'
import { FormField } from '../../components/common/FormField'
import { SearchableSelect, SearchableSelectField } from '../../components/common/SearchableSelect'
import { PageHeader } from '../../components/common/PageHeader'
import { SearchInput } from '../../components/common/SearchInput'
import { DataTable } from '../../components/common/DataTable'
import { EntityDialog } from '../../components/common/EntityDialog'
import { ErrorState } from '../../components/common/ErrorState'
import { ConfirmDialog } from '../../components/common/ConfirmDialog'
import { Badge } from '../../components/ui/badge'

const baseScopeFields = {
  scope_department_id: z.string().optional(),
  scope_level_ids: z.array(z.string()).optional(),
  scope_all_levels: z.boolean().default(false),
}

const editSchema = z.object({
  full_name: z.string().trim().min(2, 'الاسم مطلوب'),
  role: z.string().min(1, 'اختر الدور'),
  department_id: z.string().optional(),
  is_active: z.boolean(),
  ...baseScopeFields,
}).superRefine((values, context) => {
  if (values.role === ROLE_KEYS.DEPARTMENT_MANAGER) {
    if (!values.scope_department_id) context.addIssue({ code: z.ZodIssueCode.custom, path: ['scope_department_id'], message: 'اختر قسم نطاق الإدارة' })
    if (!values.scope_all_levels && !values.scope_level_ids?.length) context.addIssue({ code: z.ZodIssueCode.custom, path: ['scope_level_ids'], message: 'اختر مستوى واحدًا على الأقل أو جميع المستويات' })
  }
})

const inviteSchema = z.object({
  email: z.string().email('أدخل بريدًا صحيحًا'),
  full_name: z.string().trim().min(2, 'الاسم مطلوب'),
  role: z.string().min(1, 'اختر الدور'),
  department_id: z.string().optional(),
  ...baseScopeFields,
}).superRefine((values, context) => {
  if (values.role === ROLE_KEYS.DEPARTMENT_MANAGER) {
    if (!values.scope_department_id) context.addIssue({ code: z.ZodIssueCode.custom, path: ['scope_department_id'], message: 'اختر قسم نطاق الإدارة' })
    if (!values.scope_all_levels && !values.scope_level_ids?.length) context.addIssue({ code: z.ZodIssueCode.custom, path: ['scope_level_ids'], message: 'اختر مستوى واحدًا على الأقل أو جميع المستويات' })
  }
})

const roleOptions = Object.entries(ROLE_LABELS)

function scopesFromValues(values) {
  if (values.role !== ROLE_KEYS.DEPARTMENT_MANAGER) return []
  const departmentId = Number(values.scope_department_id || values.department_id)
  if (!departmentId) return []
  if (values.scope_all_levels) return [{ department_id: departmentId, level_id: null }]
  return (values.scope_level_ids || []).map((levelId) => ({ department_id: departmentId, level_id: Number(levelId) }))
}

function defaultScopeValues(user) {
  const scopes = user?.departmentScopes || []
  const allLevelsScope = scopes.find((scope) => scope.level_id === null || scope.level_id === undefined)
  return {
    department_id: user?.department_id ? String(user.department_id) : '',
    scope_department_id: String(allLevelsScope?.department_id || scopes[0]?.department_id || user?.department_id || ''),
    // No explicit Scope is fail-closed in the database. Do not silently
    // convert a legacy manager into an all-level manager while editing.
    scope_all_levels: Boolean(allLevelsScope),
    scope_level_ids: scopes.filter((scope) => scope.level_id !== null && scope.level_id !== undefined).map((scope) => String(scope.level_id)),
  }
}

export function Users() {
  usePageTitle('المستخدمون')
  const { profile } = useAuth()
  const queryClient = useQueryClient()
  const [search, setSearch] = useState('')
  const [roleFilter, setRoleFilter] = useState('')
  const [editing, setEditing] = useState(null)
  const [inviteOpen, setInviteOpen] = useState(false)
  const [toggling, setToggling] = useState(null)
  const [error, setError] = useState(null)
  const users = useQuery({ queryKey: ['users'], queryFn: usersService.list, enabled: can(profile, 'users.view') })
  const departments = useQuery({ queryKey: ['departments', 'for-users'], queryFn: departmentsService.list })
  const levels = useQuery({ queryKey: ['levels', 'for-user-scopes'], queryFn: levelsService.list })
  const departmentLevels = useQuery({ queryKey: ['department-levels'], queryFn: departmentLevelsService.list })
  const update = useMutation({
    mutationFn: ({ id, values }) => {
      const scopeDepartment = values.role === ROLE_KEYS.DEPARTMENT_MANAGER ? values.scope_department_id : values.department_id
      return usersService.update(id, {
        full_name: values.full_name.trim(),
        role: values.role,
        department_id: scopeDepartment ? Number(scopeDepartment) : null,
        is_active: values.is_active,
        scopes: scopesFromValues(values),
      })
    },
    onSuccess: () => { queryClient.invalidateQueries({ queryKey: ['users'] }); setEditing(null); setError(null); toast.success('تم تحديث بيانات المستخدم ونطاقه') },
    onError: (err) => setError(err),
  })
  const toggle = useMutation({ mutationFn: ({ id, value, scopes }) => usersService.update(id, { is_active: value, scopes: scopes || [] }), onSuccess: (_data, vars) => { queryClient.invalidateQueries({ queryKey: ['users'] }); setToggling(null); toast.success(vars.value ? 'تم تفعيل الحساب' : 'تم تعطيل الحساب') }, onError: (err) => { setToggling(null); toast.error(getErrorMessage(err)) } })
  const invite = useMutation({ mutationFn: (values) => usersService.create({ email: values.email, full_name: values.full_name, role: values.role, department_id: (values.role === ROLE_KEYS.DEPARTMENT_MANAGER ? values.scope_department_id : values.department_id) ? Number(values.role === ROLE_KEYS.DEPARTMENT_MANAGER ? values.scope_department_id : values.department_id) : null, scopes: scopesFromValues(values) }), onSuccess: () => { queryClient.invalidateQueries({ queryKey: ['users'] }); setInviteOpen(false); toast.success('تم إنشاء دعوة المستخدم') }, onError: (err) => setError(err) })
  const filtered = useMemo(() => (users.data || []).filter((item) => (!roleFilter || item.role === roleFilter) && (!search || [item.full_name, item.email, item.department?.title].some((value) => String(value || '').toLocaleLowerCase('ar').includes(search.toLocaleLowerCase('ar'))))), [users.data, roleFilter, search])
  if (!can(profile, 'users.view')) return <ErrorState title="لا تملك صلاحية الوصول" error="إدارة المستخدمين متاحة لمدير النظام الأعلى فقط." />
  return <div className="page-enter"><PageHeader title="المستخدمون" description="إدارة حسابات الوصول والأدوار ونطاقات مديري الأقسام على مستوى القسم والمستويات." icon={UsersIcon} actionLabel={can(profile, 'users.manage') ? 'دعوة مستخدم' : undefined} onAction={() => { setError(null); setInviteOpen(true) }}><Badge variant="outline">{users.data?.length || 0} حساب</Badge></PageHeader><Card className="overflow-hidden"><div className="flex flex-col gap-3 border-b border-border p-4 lg:flex-row lg:items-center"><SearchInput value={search} onChange={setSearch} placeholder="ابحث بالاسم أو البريد…" className="w-full lg:max-w-sm" /><SearchableSelect value={roleFilter} onChange={setRoleFilter} options={roleOptions.map(([key, label]) => ({ value: key, label }))} placeholder="كل الأدوار" searchPlaceholder="ابحث بالدور…" className="w-full lg:min-w-48" /></div>{users.isError ? <div className="p-4"><ErrorState error={users.error} onRetry={() => users.refetch()} /></div> : <DataTable loading={users.isLoading} data={filtered} columns={[{ key: 'full_name', header: 'المستخدم', cell: (row) => <div className="flex items-center gap-3"><div className="flex h-9 w-9 items-center justify-center rounded-xl bg-primary/10 text-xs font-black text-primary">{getInitials(row.full_name || row.email)}</div><div><p className="font-bold">{row.full_name || 'بدون اسم'}</p><p className="mt-0.5 text-xs text-muted-foreground" dir="ltr">{row.email}</p></div></div> }, { key: 'role', header: 'الدور', cell: (row) => <Badge variant={row.role === ROLE_KEYS.SUPER_ADMIN ? 'default' : 'secondary'}>{getRoleLabel(row.role)}</Badge> }, { key: 'department', header: 'القسم', cell: (row) => row.department?.title || <span className="text-muted-foreground">عام / غير مرتبط</span> }, { key: 'scope', header: 'نطاق مدير القسم', cell: (row) => <ScopeSummary row={row} levels={levels.data || []} /> }, { key: 'is_active', header: 'الحالة', cell: (row) => <Badge variant={row.is_active ? 'success' : 'danger'}>{row.is_active ? <><UserCheck className="h-3.5 w-3.5" />نشط</> : <><UserX className="h-3.5 w-3.5" />معطل</>}</Badge> }, { key: 'created_at', header: 'تاريخ الإنشاء', cell: (row) => row.created_at ? new Date(row.created_at).toLocaleDateString('ar-YE') : '—' }]} actions={(row) => <div className="flex items-center gap-1">{can(profile, 'users.manage') ? <><Button variant="ghost" size="sm" className="h-8 text-primary" disabled={row.id === profile?.id} onClick={() => { setError(null); setEditing(row) }}>تعديل</Button><Button variant="ghost" size="sm" className={`h-8 ${row.is_active ? 'text-rose-600' : 'text-emerald-600'}`} disabled={row.id === profile?.id} onClick={() => setToggling(row)}>{row.is_active ? 'تعطيل' : 'تفعيل'}</Button></> : null}</div>} emptyTitle="لا توجد حسابات" emptyDescription="بعد تشغيل migration وEdge Function ستظهر الحسابات هنا." />}</Card><EntityDialog open={Boolean(editing)} onOpenChange={(open) => { if (!open) setEditing(null) }} title="تعديل مستخدم" description="اختر دور المستخدم ونطاق مدير القسم. خيار جميع المستويات ينشئ Scope بقيمة level_id = null." schema={editSchema} defaultValues={editing ? { full_name: editing.full_name || '', role: editing.role || ROLE_KEYS.VIEWER, is_active: editing.is_active !== false, ...defaultScopeValues(editing) } : { full_name: '', role: ROLE_KEYS.VIEWER, department_id: '', scope_department_id: '', scope_level_ids: [], scope_all_levels: false, is_active: true }} onSubmit={(values) => update.mutateAsync({ id: editing.id, values })} loading={update.isPending} serverError={error} renderFields={(form) => <UserFormFields form={form} departments={departments.data || []} levels={levels.data || []} departmentLevels={departmentLevels.data || []} mode="edit" />} /><EntityDialog open={inviteOpen} onOpenChange={(open) => { setInviteOpen(open); if (!open) setError(null) }} title="دعوة مستخدم جديد" description="يمكن تعيين مدير القسم على كل المستويات أو مستويات محددة من نفس النموذج." schema={inviteSchema} defaultValues={{ email: '', full_name: '', role: ROLE_KEYS.VIEWER, department_id: '', scope_department_id: '', scope_level_ids: [], scope_all_levels: false }} onSubmit={(values) => invite.mutateAsync(values)} loading={invite.isPending} serverError={error} submitLabel="إنشاء الدعوة" renderFields={(form) => <UserFormFields form={form} departments={departments.data || []} levels={levels.data || []} departmentLevels={departmentLevels.data || []} mode="invite" />} /><ConfirmDialog open={Boolean(toggling)} onOpenChange={(open) => !open && setToggling(null)} title={toggling?.is_active ? 'تعطيل الحساب' : 'تفعيل الحساب'} description={toggling?.is_active ? 'لن يتمكن المستخدم من دخول النظام بعد تعطيل الحساب.' : 'سيتمكن المستخدم من دخول النظام وفق الدور المعيّن له.'} confirmLabel={toggling?.is_active ? 'تعطيل الحساب' : 'تفعيل الحساب'} onConfirm={() => toggle.mutate({ id: toggling.id, value: !toggling.is_active, scopes: toggling.departmentScopes || [] })} loading={toggle.isPending} destructive={toggling?.is_active} /></div>
}

function UserFormFields({ form, departments, levels, departmentLevels, mode }) {
  const { register, formState: { errors }, watch, setValue } = form
  const role = watch('role')
  return <>{mode === 'invite' ? <FormField label="البريد الإلكتروني" name="email" required error={errors.email}><Input id="email" type="email" dir="ltr" placeholder="name@university.edu" {...register('email')} /></FormField> : null}<FormField label="الاسم الكامل" name="full_name" required error={errors.full_name}><Input id="full_name" {...register('full_name')} /></FormField><FormField label="الدور" name="role" required error={errors.role}><Select id="role" {...register('role')}>{roleOptions.map(([key, label]) => <option key={key} value={key}>{label}</option>)}</Select></FormField>{role !== ROLE_KEYS.DEPARTMENT_MANAGER ? <FormField label="القسم المرتبط (اختياري)" name="department_id" error={errors.department_id}><SearchableSelectField name="department_id" register={register} watch={watch} setValue={setValue} options={departments.map((item) => ({ value: item.id, label: `${item.abbreviation} — ${item.title}`, searchText: `${item.abbreviation} ${item.title}` }))} placeholder="بدون قسم" searchPlaceholder="ابحث باسم القسم…" /></FormField> : null}{role === ROLE_KEYS.DEPARTMENT_MANAGER ? <DepartmentScopeFields register={register} errors={errors} watch={watch} setValue={setValue} departments={departments} levels={levels} departmentLevels={departmentLevels} /> : null}{mode === 'edit' ? <div className="flex items-center justify-between rounded-xl border border-border bg-muted/40 p-3"><div><p className="text-sm font-semibold">الحساب نشط</p><p className="mt-1 text-xs text-muted-foreground">الحساب المعطل لا يستطيع دخول لوحة التحكم.</p></div><input type="checkbox" className="h-4 w-4 accent-primary" {...register('is_active')} /></div> : null}</>
}

function DepartmentScopeFields({ register, errors, watch, setValue, departments, levels, departmentLevels }) {
  const allLevels = Boolean(watch('scope_all_levels'))
  const departmentValue = watch('scope_department_id') || ''
  const allowedLevelIds = new Set(departmentLevels.filter((item) => String(item.department_id) === String(departmentValue)).map((item) => String(item.level_id)))
  const availableLevels = levels.filter((level) => allowedLevelIds.has(String(level.id)))
  return <div className="space-y-4 rounded-2xl border border-primary/20 bg-primary/[.025] p-4"><div className="flex items-start gap-3"><div className="flex h-9 w-9 items-center justify-center rounded-xl bg-primary/10 text-primary"><Building2 className="h-4 w-4" /></div><div><p className="text-sm font-black">نطاق مدير القسم</p><p className="mt-1 text-xs leading-5 text-muted-foreground">حدّد قسمًا ثم اختر جميع المستويات أو مستويات محددة.</p></div></div><FormField label="قسم النطاق" name="scope_department_id" required error={errors.scope_department_id}><SearchableSelectField name="scope_department_id" register={register} watch={watch} setValue={(name, value, options) => { setValue(name, value, options); setValue('department_id', value, options) }} options={departments.map((item) => ({ value: item.id, label: `${item.abbreviation} — ${item.title}`, searchText: `${item.abbreviation} ${item.title}` }))} placeholder="اختر القسم" searchPlaceholder="ابحث باسم القسم…" /></FormField><label className="flex items-center gap-2 rounded-xl border border-border bg-background/70 p-3 text-sm font-bold"><input type="checkbox" className="h-4 w-4 accent-primary" {...register('scope_all_levels')} />مسؤول عن جميع مستويات القسم</label>{!allLevels ? <div className="space-y-2"><p className="flex items-center gap-2 text-xs font-bold text-muted-foreground"><Layers3 className="h-4 w-4 text-primary" />المستويات المسموح بها</p><div className="grid gap-2 sm:grid-cols-2">{availableLevels.map((level) => <label key={level.id} className="flex items-center gap-2 rounded-lg border border-border bg-background/70 p-2 text-xs font-semibold"><input type="checkbox" value={String(level.id)} className="h-4 w-4 accent-primary" {...register('scope_level_ids')} />{level.title}</label>)}</div>{departmentValue && !availableLevels.length ? <p className="rounded-lg bg-amber-500/10 p-2 text-xs leading-5 text-amber-700 dark:text-amber-300">لا توجد مستويات مرتبطة بهذا القسم بعد. أنشئ Batch لهذا القسم والمستوى أو أضف الربط من RPC إدارة department_levels.</p> : null}{errors.scope_level_ids ? <p className="text-xs font-medium text-rose-600">{errors.scope_level_ids.message}</p> : null}</div> : <p className="rounded-xl bg-emerald-500/10 p-3 text-xs font-semibold leading-5 text-emerald-700 dark:text-emerald-300">سيتم إنشاء Scope واحد بقيمة `level_id = null` ويعني جميع مستويات القسم.</p>}{departmentValue ? <input type="hidden" {...register('department_id')} value={departmentValue} /> : null}</div>
}

function ScopeSummary({ row, levels }) {
  if (row.role !== ROLE_KEYS.DEPARTMENT_MANAGER) return <span className="text-muted-foreground">—</span>
  const scopes = row.departmentScopes || []
  if (!scopes.length) return <Badge variant="warning">لا يوجد Scope (مغلق)</Badge>
  if (scopes.some((scope) => scope.level_id === null || scope.level_id === undefined)) return <Badge variant="info">كل المستويات</Badge>
  const labels = scopes.map((scope) => levels.find((level) => level.id === scope.level_id)?.title || `#${scope.level_id}`)
  return <span className="max-w-48 truncate text-xs font-semibold">{labels.join('، ')}</span>
}
