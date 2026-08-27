import { useMemo, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Check, ShieldCheck, SlidersHorizontal } from 'lucide-react'
import { toast } from 'sonner'
import { rolesService } from '../../services/rolesService'
import { ROLE_KEYS, can, getRoleDescription, getRoleLabel } from '../../lib/permissions'
import { useAuth } from '../../context/AuthContext'
import { usePageTitle } from '../../hooks/usePageTitle'
import { Card, CardContent, CardHeader, CardTitle } from '../../components/ui/card'
import { Button } from '../../components/ui/button'
import { Badge } from '../../components/ui/badge'
import { ErrorState } from '../../components/common/ErrorState'
import { LoadingState } from '../../components/common/LoadingState'
import { EmptyState } from '../../components/common/EmptyState'

export function Roles() {
  usePageTitle('الأدوار والصلاحيات')
  const { profile } = useAuth()
  const queryClient = useQueryClient()
  const [selectedRole, setSelectedRole] = useState(ROLE_KEYS.ADMIN)
  const query = useQuery({ queryKey: ['roles'], queryFn: rolesService.list, enabled: can(profile, 'roles.view') })
  const mutation = useMutation({ mutationFn: ({ roleKey, permissionKey, enabled }) => rolesService.setPermission(roleKey, permissionKey, enabled), onSuccess: () => { queryClient.invalidateQueries({ queryKey: ['roles'] }); toast.success('تم تحديث الصلاحية') }, onError: () => toast.error('تعذر تحديث الصلاحية. تأكد من تطبيق migration.') })
  const roles = query.data?.roles || []
  const permissions = query.data?.permissions || []
  const links = query.data?.links || []
  const role = roles.find((item) => item.key === selectedRole) || roles[0]
  const activePermissions = useMemo(() => new Set(links.filter((item) => item.role_key === role?.key).map((item) => item.permission_key)), [links, role?.key])
  if (!can(profile, 'roles.view')) return <ErrorState title="لا تملك صلاحية الوصول" error="إدارة الأدوار والصلاحيات متاحة لمدير النظام الأعلى فقط." />
  if (query.isLoading) return <LoadingState rows={8} />
  if (query.isError) return <ErrorState error={query.error} onRetry={() => query.refetch()} />
  if (!roles.length || !permissions.length) return <EmptyState title="لم يتم تجهيز نموذج الصلاحيات" description="طبّق supabase/schema.sql لتهيئة الأدوار والصلاحيات القابلة للتعديل." />
  return <div className="page-enter"><div className="mb-6"><p className="mb-1 text-xs font-bold uppercase tracking-[.16em] text-primary">الحوكمة والوصول</p><h1 className="text-2xl font-black tracking-tight sm:text-3xl">الأدوار والصلاحيات</h1><p className="mt-1 max-w-2xl text-sm leading-6 text-muted-foreground">تحكم مركزي بالصلاحيات المخزنة في قاعدة البيانات. حماية الواجهة ليست بديلًا عن RLS.</p></div><div className="grid gap-5 xl:grid-cols-[280px_1fr]"><Card className="h-fit"><CardHeader><CardTitle className="flex items-center gap-2"><ShieldCheck className="h-5 w-5 text-primary" />الأدوار</CardTitle></CardHeader><CardContent className="space-y-2">{roles.map((item) => <button type="button" key={item.key} onClick={() => setSelectedRole(item.key)} className={`w-full rounded-xl border p-3 text-right transition-all ${role?.key === item.key ? 'border-primary bg-primary/5 shadow-sm' : 'border-border hover:bg-muted/50'}`}><div className="flex items-center justify-between gap-2"><span className="text-sm font-bold">{item.label_ar || getRoleLabel(item.key)}</span>{item.key === ROLE_KEYS.SUPER_ADMIN ? <Badge>كامل</Badge> : null}</div><p className="mt-1 text-[11px] leading-5 text-muted-foreground">{item.description || getRoleDescription(item.key)}</p></button>)}</CardContent></Card><Card><CardHeader className="flex-col gap-3 sm:flex-row sm:items-center sm:justify-between"><div><CardTitle className="flex items-center gap-2"><SlidersHorizontal className="h-5 w-5 text-primary" />صلاحيات {role?.label_ar || getRoleLabel(role?.key)}</CardTitle><p className="mt-1 text-xs text-muted-foreground">التغييرات تحفظ مباشرة في role_permissions.</p></div><Badge variant="outline">{activePermissions.size} مفعّلة</Badge></CardHeader><CardContent><div className="grid gap-2 sm:grid-cols-2 xl:grid-cols-3">{permissions.map((permission) => { const enabled = role?.key === ROLE_KEYS.SUPER_ADMIN || activePermissions.has(permission.key); return <div key={permission.key} className={`flex items-center justify-between gap-3 rounded-xl border p-3 ${enabled ? 'border-primary/20 bg-primary/[.025]' : 'border-border'}`}><div className="min-w-0"><p className="truncate text-sm font-bold">{permission.label_ar || permission.key}</p><p className="mt-1 truncate font-mono text-[10px] text-muted-foreground" dir="ltr">{permission.key}</p></div>{role?.key === ROLE_KEYS.SUPER_ADMIN ? <span className="flex h-7 w-7 items-center justify-center rounded-lg bg-primary/10 text-primary"><Check className="h-4 w-4" /></span> : <Button variant={enabled ? 'default' : 'outline'} size="sm" className="h-8 shrink-0" disabled={mutation.isPending} onClick={() => mutation.mutate({ roleKey: role.key, permissionKey: permission.key, enabled: !enabled })}>{enabled ? 'مفعّلة' : 'تفعيل'}</Button>}</div> })}</div></CardContent></Card></div></div>
}
