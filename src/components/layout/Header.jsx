import { Bell, CalendarClock, ChevronDown, DoorOpen, Menu, Moon, Search, Sun, UserRound, X } from 'lucide-react'
import { useQuery } from '@tanstack/react-query'
import { useState } from 'react'
import { useLocation, useNavigate } from 'react-router-dom'
import { useAuth } from '../../context/AuthContext'
import { useTheme } from '../../context/ThemeContext'
import { formatRelativeDate, getInitials } from '../../lib/utils'
import { getRoleLabel } from '../../lib/permissions'
import { notificationsService } from '../../services/notificationsService'
import { Button } from '../ui/button'

const pageTitles = {
  '/dashboard': 'لوحة التحكم', '/buildings': 'المباني', '/halls': 'القاعات', '/reservations': 'حجوزات القاعات', '/departments': 'الأقسام', '/department-levels': 'ربط الأقسام بالمستويات', '/levels': 'المستويات', '/batches': 'الدفعات', '/subjects': 'المواد الدراسية', '/instructors': 'المدرسون', '/lectures': 'المحاضرات', '/schedule': 'الجدول الأسبوعي', '/conflicts': 'مركز التعارضات', '/users': 'المستخدمون', '/roles': 'الأدوار والصلاحيات', '/reports': 'التقارير', '/settings': 'الإعدادات',
}

export function Header({ onMenuClick }) {
  const { user, profile } = useAuth()
  const { theme, setTheme } = useTheme()
  const location = useLocation()
  const navigate = useNavigate()
  const [profileOpen, setProfileOpen] = useState(false)
  const [notificationsOpen, setNotificationsOpen] = useState(false)
  const [searchOpen, setSearchOpen] = useState(false)
  const [search, setSearch] = useState('')
  const notifications = useQuery({ queryKey: ['notifications'], queryFn: notificationsService.list, enabled: notificationsOpen && Boolean(profile), staleTime: 60_000 })
  const title = pageTitles[location.pathname] || 'نظام إدارة القاعات'
  const nextTheme = theme === 'dark' ? 'light' : 'dark'
  const runSearch = (event) => {
    event.preventDefault()
    const value = search.trim()
    if (!value) return
    const routes = [{ key: 'مبنى', to: '/buildings' }, { key: 'قاعة', to: '/halls' }, { key: 'حجز', to: '/reservations' }, { key: 'قسم', to: '/departments' }, { key: 'مادة', to: '/subjects' }, { key: 'مدرس', to: '/instructors' }, { key: 'محاضر', to: '/lectures' }, { key: 'جدول', to: '/schedule' }, { key: 'تعارض', to: '/conflicts' }, { key: 'تقرير', to: '/reports' }]
    const match = routes.find((item) => value.includes(item.key))
    if (match) navigate(match.to)
    setSearchOpen(false)
    setSearch('')
  }
  return <header className="sticky top-0 z-20 flex h-[78px] shrink-0 items-center justify-between border-b border-border/70 bg-background/75 px-4 backdrop-blur-2xl sm:px-6 lg:px-8">
    <div className="flex min-w-0 items-center gap-3"><Button variant="ghost" size="icon" onClick={onMenuClick} className="lg:hidden"><Menu className="h-5 w-5" /></Button><div className="min-w-0"><p className="truncate text-lg font-black">{title}</p><p className="hidden text-xs text-muted-foreground sm:block">مرحبًا بعودتك، {profile?.full_name || user?.email?.split('@')[0] || 'مستخدم'}</p></div></div>
    <div className="flex items-center gap-1.5 sm:gap-2">
      {searchOpen ? <form onSubmit={runSearch} className="relative hidden sm:block"><Search className="absolute right-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" /><input autoFocus value={search} onChange={(event) => setSearch(event.target.value)} onBlur={() => !search && setSearchOpen(false)} placeholder="ابحث عن قسم…" className="h-9 w-48 rounded-lg border border-input bg-background pe-9 ps-3 text-sm outline-none focus:border-primary" /></form> : null}
      <Button variant="ghost" size="icon" className="hidden sm:inline-flex" onClick={() => setSearchOpen((value) => !value)}>{searchOpen ? <X className="h-4 w-4" /> : <Search className="h-4 w-4" />}</Button>
      <Button variant="ghost" size="icon" onClick={() => setTheme(nextTheme)} title={theme === 'dark' ? 'الوضع الفاتح' : 'الوضع الداكن'}>{theme === 'dark' ? <Sun className="h-4 w-4" /> : <Moon className="h-4 w-4" />}</Button>
      <div className="relative"><Button variant="ghost" size="icon" className="relative" onClick={() => setNotificationsOpen((value) => !value)} aria-label="آخر التحديثات"><Bell className="h-4 w-4" />{notifications.data?.length ? <span className="absolute right-2 top-2 h-1.5 w-1.5 rounded-full bg-rose-500 ring-2 ring-background" /> : null}</Button>{notificationsOpen ? <div className="absolute left-0 top-12 z-30 w-80 rounded-xl border border-border bg-card p-3 shadow-xl"><div className="mb-2 flex items-center justify-between"><p className="text-sm font-black">آخر التحديثات</p><span className="text-[10px] text-muted-foreground">من البيانات الفعلية</span></div>{notifications.isLoading ? <p className="py-5 text-center text-xs text-muted-foreground">جارٍ التحميل…</p> : notifications.isError ? <p className="py-5 text-center text-xs text-rose-600">تعذر تحميل التحديثات</p> : notifications.data?.length ? <div className="space-y-1">{notifications.data.map((item) => <div key={item.id} className="flex items-start gap-2 rounded-lg p-2 hover:bg-muted/50"><div className="mt-0.5 flex h-7 w-7 shrink-0 items-center justify-center rounded-lg bg-primary/10 text-primary">{item.type === 'lecture' ? <CalendarClock className="h-3.5 w-3.5" /> : <DoorOpen className="h-3.5 w-3.5" />}</div><div className="min-w-0"><p className="truncate text-xs font-semibold">{item.title}</p><p className="mt-1 text-[10px] text-muted-foreground">{formatRelativeDate(item.date)}</p></div></div>)}</div> : <p className="py-5 text-center text-xs text-muted-foreground">لا توجد تحديثات حديثة</p>}</div> : null}</div>
      <div className="relative mr-1"><button type="button" onClick={() => setProfileOpen((value) => !value)} className="flex items-center gap-2 rounded-xl p-1.5 transition-colors hover:bg-muted"><div className="flex h-9 w-9 items-center justify-center rounded-xl bg-gradient-to-br from-indigo-500 to-primary text-xs font-black text-white">{getInitials(profile?.full_name || user?.email)}</div><div className="hidden text-right md:block"><p className="max-w-28 truncate text-xs font-bold">{profile?.full_name || user?.email || 'مستخدم'}</p><p className="text-[10px] text-muted-foreground">{getRoleLabel(profile?.role)}</p></div><ChevronDown className="hidden h-4 w-4 text-muted-foreground md:block" /></button>{profileOpen ? <div className="absolute left-0 top-12 z-30 w-56 rounded-xl border border-border bg-card p-2 shadow-xl"><div className="flex items-center gap-2 rounded-lg bg-muted/60 p-2"><div className="flex h-8 w-8 items-center justify-center rounded-lg bg-primary/10 text-primary"><UserRound className="h-4 w-4" /></div><div className="min-w-0"><p className="truncate text-xs font-bold">{profile?.full_name || 'مستخدم النظام'}</p><p className="truncate text-[10px] text-muted-foreground">{user?.email}</p></div></div><button type="button" onClick={() => { setProfileOpen(false); navigate('/settings') }} className="mt-1 flex w-full items-center gap-2 rounded-lg px-2 py-2 text-right text-xs font-semibold text-muted-foreground hover:bg-muted hover:text-foreground"><UserRound className="h-4 w-4" />إعدادات الملف الشخصي</button></div> : null}</div>
    </div>
  </header>
}
