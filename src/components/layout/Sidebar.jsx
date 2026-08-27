import { NavLink, useLocation, useNavigate } from 'react-router-dom'
import { BarChart3, BookOpen, Building2, CalendarDays, ChevronLeft, ClipboardList, DoorOpen, GraduationCap, LayoutDashboard, Layers3, Library, LogOut, Settings, ShieldCheck, TriangleAlert, UserRound, Users, X } from 'lucide-react'
import { useAuth } from '../../context/AuthContext'
import { can, getRoleLabel, isSuperAdmin } from '../../lib/permissions'
import { getInitials } from '../../lib/utils'
import { supabase } from '../../lib/supabase'
import { Button } from '../ui/button'
import { Separator } from '../ui/separator'

const groups = [
  {
    label: 'نظرة عامة',
    items: [{ to: '/dashboard', label: 'لوحة التحكم', icon: LayoutDashboard, permission: 'dashboard.view' }],
  },
  {
    label: 'الإدارة الأكاديمية',
    items: [
      { to: '/departments', label: 'الأقسام', icon: GraduationCap, permission: 'departments.view' },
      { to: '/department-levels', label: 'ربط الأقسام بالمستويات', icon: Layers3, permission: 'departments.update' },
      { to: '/levels', label: 'المستويات', icon: Library, permission: 'levels.view' },
      { to: '/batches', label: 'الدفعات', icon: Users, permission: 'batches.view' },
      { to: '/subjects', label: 'المواد', icon: BookOpen, permission: 'subjects.view' },
      { to: '/instructors', label: 'المدرسون', icon: UserRound, permission: 'instructors.view' },
    ],
  },
  {
    label: 'إدارة المرافق',
    items: [
      { to: '/buildings', label: 'المباني', icon: Building2, permission: 'buildings.view' },
      { to: '/halls', label: 'القاعات', icon: DoorOpen, permission: 'halls.view' },
      { to: '/reservations', label: 'حجوزات القاعات', icon: CalendarDays, permission: 'hall_reservations.view' },
    ],
  },
  {
    label: 'الجدول الدراسي',
    items: [
      { to: '/lectures', label: 'المحاضرات', icon: ClipboardList, permission: 'lectures.view' },
      { to: '/schedule', label: 'الجدول الأسبوعي', icon: CalendarDays, permission: 'lectures.view' },
      { to: '/conflicts', label: 'مركز التعارضات', icon: TriangleAlert, permission: 'lectures.view' },
    ],
  },
  {
    label: 'التحليلات والإدارة',
    items: [
      { to: '/reports', label: 'التقارير', icon: BarChart3, permission: 'reports.view' },
      { to: '/users', label: 'المستخدمون', icon: Users, permission: 'users.view', superAdmin: true },
      { to: '/roles', label: 'الأدوار والصلاحيات', icon: ShieldCheck, permission: 'roles.view', superAdmin: true },
      { to: '/settings', label: 'الإعدادات', icon: Settings, permission: 'settings.view' },
    ],
  },
]

export function Sidebar({ open, onClose }) {
  const { profile } = useAuth()
  const location = useLocation()
  const navigate = useNavigate()
  const handleLogout = async () => {
    await supabase.auth.signOut()
    navigate('/login', { replace: true })
  }
  return <>
    {open ? <div className="fixed inset-0 z-30 bg-slate-950/40 lg:hidden" onClick={onClose} /> : null}
    <aside className={`fixed inset-y-0 right-0 z-40 flex w-[288px] flex-col border-l border-border/80 bg-gradient-to-b from-card via-card to-background shadow-2xl backdrop-blur-xl transition-transform duration-300 lg:static lg:z-auto lg:translate-x-0 lg:shadow-none ${open ? 'translate-x-0' : 'translate-x-full'}`}>
      <div className="relative flex h-[82px] shrink-0 items-center justify-between overflow-hidden border-b border-border/70 px-5">
        <div className="absolute -left-10 -top-14 h-32 w-32 rounded-full bg-primary/10 blur-2xl" />
        <div className="relative flex items-center gap-3"><div className="flex h-11 w-11 items-center justify-center rounded-2xl bg-gradient-to-br from-primary to-indigo-500 text-lg font-black text-white shadow-lg shadow-primary/25">ج</div><div><p className="text-sm font-black tracking-tight">إدارة القاعات</p><p className="mt-0.5 text-[10px] font-semibold text-muted-foreground">University Hall System</p></div></div><Button variant="ghost" size="icon" className="relative lg:hidden" onClick={onClose}><X className="h-5 w-5" /></Button>
      </div>
      <div className="flex-1 overflow-y-auto px-3 py-5">
        {groups.map((group) => {
          const items = group.items.filter((item) => can(profile, item.permission) && (!item.superAdmin || isSuperAdmin(profile)))
          if (!items.length) return null
          return <div key={group.label} className="mb-6"><p className="mb-2.5 px-3 text-[10px] font-black uppercase tracking-[.18em] text-muted-foreground/80">{group.label}</p><nav className="space-y-1.5">{items.map((item) => { const active = location.pathname === item.to || (item.to !== '/dashboard' && location.pathname.startsWith(`${item.to}/`)); return <NavLink key={item.to} to={item.to} onClick={onClose} className={`group flex items-center gap-3 rounded-xl px-3 py-2.5 text-sm font-bold transition-all ${active ? 'bg-primary text-primary-foreground shadow-md shadow-primary/20 ring-1 ring-primary/25' : 'text-muted-foreground hover:bg-primary/[.06] hover:text-foreground'}`}><item.icon className={`h-[18px] w-[18px] shrink-0 transition-colors ${active ? 'text-primary-foreground' : 'text-muted-foreground group-hover:text-primary'}`} /><span className="flex-1">{item.label}</span>{active ? <ChevronLeft className="h-4 w-4 opacity-70" /> : null}</NavLink> })}</nav></div>
        })}
      </div>
      <div className="shrink-0 p-3"><div className="mb-3 rounded-2xl border border-border/80 bg-muted/35 p-3"><div className="flex items-center gap-2.5"><div className="flex h-9 w-9 items-center justify-center rounded-xl bg-primary/10 text-xs font-black text-primary">{getInitials(profile?.full_name)}</div><div className="min-w-0"><p className="truncate text-xs font-black">{profile?.full_name || 'مستخدم النظام'}</p><p className="mt-0.5 truncate text-[10px] font-semibold text-muted-foreground">{getRoleLabel(profile?.role)}</p></div><span className="mr-auto h-2 w-2 rounded-full bg-emerald-500" /></div></div><Separator className="mb-3" /><button type="button" onClick={handleLogout} className="flex w-full items-center gap-3 rounded-xl px-3 py-2.5 text-sm font-bold text-muted-foreground transition-colors hover:bg-rose-500/10 hover:text-rose-600"><LogOut className="h-[18px] w-[18px]" />تسجيل الخروج</button></div>
    </aside>
  </>
}
