import { Navigate, Outlet, useLocation } from 'react-router-dom'
import { ShieldAlert } from 'lucide-react'
import { useAuth } from '../context/AuthContext'
import { can, normalizeRole } from '../lib/permissions'
import { LoadingState } from '../components/common/LoadingState'

export function ProtectedRoute() {
  const { session, profile, loading, profileLoading, setupRequired } = useAuth()
  const location = useLocation()
  if (loading || profileLoading) return <div className="min-h-screen bg-background p-6"><div className="mx-auto max-w-3xl pt-20"><LoadingState rows={4} /></div></div>
  if (!session) return <Navigate to="/login" replace state={{ from: location.pathname }} />
  if (setupRequired) return <SetupRequired />
  if (!profile) return <ProfileMissing />
  if (profile.is_active === false) return <ProfileMissing inactive />
  return <Outlet />
}

export function PermissionGuard({ permission, children }) {
  const { profile } = useAuth()
  if (!can(profile, permission)) return <div className="mx-auto max-w-2xl py-12"><ProfileMissing forbidden /></div>
  return children
}

export function RoleGuard({ roles = [], children }) {
  const { profile } = useAuth()
  const currentRole = normalizeRole(profile?.role)
  if (!roles.map((role) => normalizeRole(role)).includes(currentRole)) return <div className="mx-auto max-w-2xl py-12"><ProfileMissing forbidden /></div>
  return children
}

function ProfileMissing({ inactive = false, forbidden = false }) {
  return <div className="flex min-h-screen items-center justify-center bg-background p-6"><div className="max-w-md rounded-2xl border border-border bg-card p-8 text-center shadow-card"><div className="mx-auto mb-4 flex h-14 w-14 items-center justify-center rounded-2xl bg-amber-500/10 text-amber-600"><ShieldAlert className="h-7 w-7" /></div><h1 className="text-xl font-black">{forbidden ? 'لا تملك صلاحية الوصول' : inactive ? 'الحساب غير نشط' : 'ملف المستخدم غير مكتمل'}</h1><p className="mt-2 text-sm leading-7 text-muted-foreground">{forbidden ? 'تواصل مع مدير النظام إذا كنت تحتاج صلاحية إضافية.' : inactive ? 'تم تعطيل حسابك. تواصل مع مدير النظام لإعادة التفعيل.' : 'تم تسجيل الدخول بنجاح، لكن لم يتم العثور على Profile مرتبط بحسابك. طبّق migration النظام ثم أنشئ Profile للمستخدم.'}</p><a href="/login" className="mt-5 inline-flex rounded-lg bg-primary px-4 py-2 text-sm font-bold text-primary-foreground">العودة لتسجيل الدخول</a></div></div>
}

function SetupRequired() {
  return <div className="flex min-h-screen items-center justify-center bg-background p-6"><div className="max-w-lg rounded-2xl border border-border bg-card p-8 text-center shadow-card"><div className="mx-auto mb-4 flex h-14 w-14 items-center justify-center rounded-2xl bg-primary/10 text-primary"><ShieldAlert className="h-7 w-7" /></div><h1 className="text-xl font-black">يلزم تجهيز جداول النظام</h1><p className="mt-2 text-sm leading-7 text-muted-foreground">قاعدة البيانات متصلة، لكن جداول profiles وroles غير موجودة بعد. نفّذ الملف <code className="rounded bg-muted px-1.5 py-0.5 text-xs">supabase/schema.sql</code> من SQL Editor في مشروع Supabase ثم أعد المحاولة.</p><a href="/login" className="mt-5 inline-flex rounded-lg bg-primary px-4 py-2 text-sm font-bold text-primary-foreground">العودة لتسجيل الدخول</a></div></div>
}
