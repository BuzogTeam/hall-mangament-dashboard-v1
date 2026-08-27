import { useEffect, useState } from 'react'
import { useForm } from 'react-hook-form'
import { z } from 'zod'
import { zodResolver } from '@hookform/resolvers/zod'
import { KeyRound, Palette, Save, Settings as SettingsIcon, UserRound } from 'lucide-react'
import { toast } from 'sonner'
import { useAuth } from '../../context/AuthContext'
import { useTheme } from '../../context/ThemeContext'
import { updatePassword, updateProfile } from '../../services/authService'
import { getErrorMessage, getInitials } from '../../lib/utils'
import { getRoleLabel } from '../../lib/permissions'
import { usePageTitle } from '../../hooks/usePageTitle'
import { Card, CardContent, CardHeader, CardTitle } from '../../components/ui/card'
import { Button } from '../../components/ui/button'
import { Input } from '../../components/ui/input'
import { Label } from '../../components/ui/label'
import { Select } from '../../components/ui/select'
import { FormField } from '../../components/common/FormField'
import { Alert } from '../../components/ui/alert'

const profileSchema = z.object({ full_name: z.string().trim().min(2, 'الاسم مطلوب') })
const passwordSchema = z.object({ password: z.string().min(6, 'كلمة المرور يجب أن تكون 6 أحرف على الأقل'), confirm: z.string().min(6, 'أعد كتابة كلمة المرور') }).refine((values) => values.password === values.confirm, { path: ['confirm'], message: 'كلمتا المرور غير متطابقتين' })

export function Settings() {
  usePageTitle('الإعدادات')
  const { user, profile, refreshProfile } = useAuth()
  const { theme, setTheme } = useTheme()
  const [profileError, setProfileError] = useState('')
  const [passwordError, setPasswordError] = useState('')
  const profileForm = useForm({ resolver: zodResolver(profileSchema), defaultValues: { full_name: profile?.full_name || '' } })
  const passwordForm = useForm({ resolver: zodResolver(passwordSchema), defaultValues: { password: '', confirm: '' } })
  useEffect(() => { profileForm.reset({ full_name: profile?.full_name || '' }) }, [profile?.full_name])
  const saveProfile = async (values) => { setProfileError(''); try { await updateProfile(user.id, { full_name: values.full_name.trim() }); await refreshProfile(); toast.success('تم حفظ بيانات الملف الشخصي') } catch (error) { setProfileError(getErrorMessage(error)) } }
  const savePassword = async (values) => { setPasswordError(''); try { await updatePassword(values.password); passwordForm.reset(); toast.success('تم تغيير كلمة المرور') } catch (error) { setPasswordError(getErrorMessage(error)) } }
  return <div className="page-enter"><div className="mb-6"><p className="mb-1 text-xs font-bold uppercase tracking-[.16em] text-primary">تخصيص الحساب</p><h1 className="text-2xl font-black tracking-tight sm:text-3xl">الإعدادات</h1><p className="mt-1 text-sm leading-6 text-muted-foreground">حدّث بياناتك الشخصية وتفضيلات واجهة النظام.</p></div><div className="grid gap-5 xl:grid-cols-[1fr_.8fr]"><div className="space-y-5"><Card><CardHeader><CardTitle className="flex items-center gap-2"><UserRound className="h-5 w-5 text-primary" />الملف الشخصي</CardTitle></CardHeader><CardContent><div className="mb-6 flex items-center gap-4 rounded-2xl bg-muted/50 p-4"><div className="flex h-14 w-14 items-center justify-center rounded-2xl bg-gradient-to-br from-primary to-indigo-500 text-lg font-black text-white">{getInitials(profile?.full_name || user?.email)}</div><div><p className="font-bold">{profile?.full_name || 'بدون اسم'}</p><p className="mt-1 text-xs text-muted-foreground" dir="ltr">{user?.email}</p></div></div>{profileError ? <Alert variant="destructive" className="mb-4">{profileError}</Alert> : null}<form onSubmit={profileForm.handleSubmit(saveProfile)} className="space-y-4"><FormField label="الاسم الكامل" name="full_name" required error={profileForm.formState.errors.full_name}><Input id="full_name" {...profileForm.register('full_name')} /></FormField><div><Label>البريد الإلكتروني</Label><Input value={user?.email || ''} disabled dir="ltr" /></div><div><Label>الدور</Label><Input value={getRoleLabel(profile?.role)} disabled /></div><div className="flex justify-start"><Button type="submit" disabled={profileForm.formState.isSubmitting}><Save className="h-4 w-4" />{profileForm.formState.isSubmitting ? 'جارٍ الحفظ…' : 'حفظ البيانات'}</Button></div></form></CardContent></Card><Card><CardHeader><CardTitle className="flex items-center gap-2"><KeyRound className="h-5 w-5 text-primary" />تغيير كلمة المرور</CardTitle></CardHeader><CardContent>{passwordError ? <Alert variant="destructive" className="mb-4">{passwordError}</Alert> : null}<form onSubmit={passwordForm.handleSubmit(savePassword)} className="space-y-4"><FormField label="كلمة المرور الجديدة" name="password" required error={passwordForm.formState.errors.password}><Input id="password" type="password" autoComplete="new-password" {...passwordForm.register('password')} /></FormField><FormField label="تأكيد كلمة المرور" name="confirm" required error={passwordForm.formState.errors.confirm}><Input id="confirm" type="password" autoComplete="new-password" {...passwordForm.register('confirm')} /></FormField><Button type="submit" variant="outline" disabled={passwordForm.formState.isSubmitting}><KeyRound className="h-4 w-4" />{passwordForm.formState.isSubmitting ? 'جارٍ التحديث…' : 'تحديث كلمة المرور'}</Button></form></CardContent></Card></div><div className="space-y-5"><Card><CardHeader><CardTitle className="flex items-center gap-2"><Palette className="h-5 w-5 text-primary" />المظهر</CardTitle></CardHeader><CardContent><div className="space-y-3"><Label htmlFor="theme">نمط العرض</Label><Select id="theme" value={theme} onChange={(event) => setTheme(event.target.value)}><option value="light">الوضع الفاتح</option><option value="dark">الوضع الداكن</option><option value="system">حسب إعداد الجهاز</option></Select><p className="text-xs leading-6 text-muted-foreground">يتم حفظ اختيارك محليًا على هذا الجهاز.</p></div><div className="mt-6 grid grid-cols-3 gap-2"><ThemePreview active={theme === 'light'} label="فاتح" tone="light" onClick={() => setTheme('light')} /><ThemePreview active={theme === 'dark'} label="داكن" tone="dark" onClick={() => setTheme('dark')} /><ThemePreview active={theme === 'system'} label="النظام" tone="system" onClick={() => setTheme('system')} /></div></CardContent></Card><Card className="soft-grid"><CardHeader><CardTitle className="flex items-center gap-2"><SettingsIcon className="h-5 w-5 text-primary" />هيكل اللغة</CardTitle></CardHeader><CardContent><p className="text-sm leading-7 text-muted-foreground">الواجهة الحالية عربية وRTL. تم إبقاء بنية الترجمة منفصلة لتسهيل إضافة الإنجليزية أو لغات أخرى مستقبلًا.</p><div className="mt-4 rounded-xl border border-border bg-card/80 p-3 text-xs text-muted-foreground">المنطقة الزمنية: توقيت الجهاز المحلي<br />مصدر البيانات: Supabase</div></CardContent></Card></div></div></div>
}

function ThemePreview({ active, label, tone, onClick }) { return <button type="button" onClick={onClick} className={`rounded-xl border p-2 text-center transition-all ${active ? 'border-primary ring-2 ring-primary/15' : 'border-border hover:border-primary/40'}`}><div className={`h-12 rounded-lg ${tone === 'dark' ? 'bg-slate-900' : tone === 'system' ? 'bg-slate-100 dark:bg-slate-900' : 'bg-slate-100'}`}><div className="mx-auto mt-2 h-2 w-8 rounded bg-primary/60" /></div><p className="mt-2 text-[11px] font-bold">{label}</p></button> }
