import { Building2 } from 'lucide-react'
import { z } from 'zod'
import { CrudResourcePage } from '../../components/common/CrudResourcePage'
import { FormField } from '../../components/common/FormField'
import { Input } from '../../components/ui/input'
import { buildingsService } from '../../services/buildingsService'
import { usePageTitle } from '../../hooks/usePageTitle'

const schema = z.object({ title: z.string().trim().min(2, 'اسم المبنى مطلوب') })

export function Buildings() {
  usePageTitle('المباني')
  return <div className="page-enter"><CrudResourcePage title="المباني" description="نظّم مباني الجامعة وتابع ارتباطها بالقاعات الدراسية." icon={Building2} resource="buildings" queryKey="buildings" service={buildingsService} schema={schema} defaultValues={{ title: '' }} searchPlaceholder="ابحث باسم المبنى…" searchFields={['title']} emptyTitle="لا توجد مبانٍ حاليًا" emptyDescription="أضف أول مبنى ليظهر في خيارات القاعات والجداول." columns={[{ key: 'title', header: 'اسم المبنى', cell: (row) => <span className="font-bold">{row.title || 'بدون اسم'}</span> }, { key: 'id', header: 'المعرّف', cell: (row) => <span className="font-mono text-xs text-muted-foreground">#{row.id}</span> }, { key: 'created_at', header: 'تاريخ الإضافة', cell: (row) => new Date(row.created_at).toLocaleDateString('ar-YE') }]} renderFields={({ register, formState: { errors } }) => <FormField label="اسم المبنى" name="title" required error={errors.title}><Input id="title" placeholder="مثال: مبنى كلية الهندسة" {...register('title')} /></FormField>} deleteDescription="قد يفشل الحذف إذا كانت هناك قاعات مرتبطة بهذا المبنى. عالج القاعات المرتبطة أولًا." /></div>
}
