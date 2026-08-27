import { Layers3 } from 'lucide-react'
import { z } from 'zod'
import { CrudResourcePage } from '../../components/common/CrudResourcePage'
import { FormField } from '../../components/common/FormField'
import { Input } from '../../components/ui/input'
import { levelsService } from '../../services/levelsService'
import { usePageTitle } from '../../hooks/usePageTitle'

const schema = z.object({ title: z.string().trim().min(2, 'اسم المستوى مطلوب') })

export function Levels() {
  usePageTitle('المستويات')
  return <div className="page-enter"><CrudResourcePage title="المستويات الدراسية" description="تعريف المستويات التي تستخدمها الأقسام والدفعات في الجداول." icon={Layers3} resource="levels" queryKey="levels" service={levelsService} schema={schema} defaultValues={{ title: '' }} searchPlaceholder="ابحث باسم المستوى…" searchFields={['title']} columns={[{ key: 'title', header: 'المستوى', cell: (row) => <span className="font-bold">{row.title}</span> }, { key: 'id', header: 'الترتيب', cell: (row) => <span className="flex h-7 w-7 items-center justify-center rounded-lg bg-muted text-xs font-bold">{row.id}</span> }, { key: 'created_at', header: 'تاريخ الإضافة', cell: (row) => new Date(row.created_at).toLocaleDateString('ar-YE') }]} renderFields={({ register, formState: { errors } }) => <FormField label="اسم المستوى" name="title" required error={errors.title}><Input id="title" placeholder="مثال: المستوى الأول" {...register('title')} /></FormField>} deleteDescription="قد لا يمكن حذف المستوى إذا كانت هناك دفعات مرتبطة به." /></div>
}
