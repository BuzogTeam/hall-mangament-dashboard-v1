import { GraduationCap } from 'lucide-react'
import { z } from 'zod'
import { CrudResourcePage } from '../../components/common/CrudResourcePage'
import { FormField } from '../../components/common/FormField'
import { Input } from '../../components/ui/input'
import { departmentsService } from '../../services/departmentsService'
import { usePageTitle } from '../../hooks/usePageTitle'

const schema = z.object({ title: z.string().trim().min(2, 'اسم القسم مطلوب'), abbreviation: z.string().trim().min(2, 'الاختصار مطلوب').max(10, 'الاختصار طويل'), num_levels: z.coerce.number().int().min(1, 'يجب أن يكون مستوى واحدًا على الأقل').max(20, 'عدد المستويات غير منطقي') })

export function Departments() {
  usePageTitle('الأقسام')
  return <div className="page-enter"><CrudResourcePage title="الأقسام الأكاديمية" description="إدارة الأقسام واختصاراتها وعدد المستويات التابعة لها." icon={GraduationCap} resource="departments" queryKey="departments" service={departmentsService} schema={schema} defaultValues={{ title: '', abbreviation: '', num_levels: 5 }} searchPlaceholder="ابحث باسم القسم أو الاختصار…" searchFields={['title', 'abbreviation']} columns={[{ key: 'title', header: 'القسم', cell: (row) => <div><p className="font-bold">{row.title}</p><p className="mt-0.5 text-xs text-muted-foreground">القسم الأكاديمي</p></div> }, { key: 'abbreviation', header: 'الاختصار', cell: (row) => <span className="rounded-lg bg-primary/10 px-2.5 py-1 font-mono text-xs font-bold text-primary">{row.abbreviation}</span> }, { key: 'num_levels', header: 'عدد المستويات', cell: (row) => `${row.num_levels} مستويات` }, { key: 'id', header: 'المعرّف', cell: (row) => <span className="font-mono text-xs text-muted-foreground">#{row.id}</span> }]} renderFields={({ register, formState: { errors } }) => <><FormField label="اسم القسم" name="title" required error={errors.title}><Input id="title" placeholder="مثال: هندسة البرمجيات" {...register('title')} /></FormField><div className="grid gap-4 sm:grid-cols-2"><FormField label="الاختصار" name="abbreviation" required error={errors.abbreviation} hint="يستخدم لتمييز الدفعات."><Input id="abbreviation" placeholder="SE" {...register('abbreviation')} /></FormField><FormField label="عدد المستويات" name="num_levels" required error={errors.num_levels}><Input id="num_levels" type="number" min="1" max="20" {...register('num_levels')} /></FormField></div></>} deleteDescription="لا تحذف قسمًا لديه دفعات أو بيانات مرتبطة قبل معالجة العلاقات." /></div>
}
