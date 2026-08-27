import { useQuery } from '@tanstack/react-query'
import { UserRound } from 'lucide-react'
import { z } from 'zod'
import { CrudResourcePage } from '../../components/common/CrudResourcePage'
import { FormField } from '../../components/common/FormField'
import { Input } from '../../components/ui/input'
import { Select } from '../../components/ui/select'
import { instructorsService } from '../../services/instructorsService'
import { metadataService } from '../../services/metadataService'
import { ENUM_OPTIONS } from '../../lib/utils'
import { usePageTitle } from '../../hooks/usePageTitle'

const schema = z.object({ name: z.string().trim().min(2, 'اسم المدرس مطلوب'), type: z.string().min(1, 'اختر النوع') })

export function Instructors() {
  usePageTitle('المدرسون')
  const metadata = useQuery({ queryKey: ['metadata'], queryFn: metadataService.getOptions })
  const types = metadata.data?.instructorTypes?.length ? metadata.data.instructorTypes : ENUM_OPTIONS.instructorTypes
  return <div className="page-enter"><CrudResourcePage title="المدرسون" description="دليل المدرسين وأنواعهم لاستخدامه في المحاضرات والتقارير." icon={UserRound} resource="instructors" queryKey="instructors" service={instructorsService} schema={schema} defaultValues={{ name: '', type: types[0] }} searchPlaceholder="ابحث باسم المدرس…" searchFields={['name', 'type']} filterData={(rows, filters) => rows.filter((row) => !filters.type || row.type === filters.type)} renderToolbar={({ filters, setFilters }) => <Select value={filters.type || ''} onChange={(event) => setFilters((current) => ({ ...current, type: event.target.value }))} className="h-9 w-auto min-w-32 text-xs"><option value="">كل الأنواع</option>{types.map((type) => <option key={type} value={type}>{type}</option>)}</Select>} columns={[{ key: 'name', header: 'الاسم', cell: (row) => <div className="flex items-center gap-3"><div className="flex h-9 w-9 items-center justify-center rounded-xl bg-primary/10 text-xs font-bold text-primary">{row.name?.trim()?.[0] || 'م'}</div><span className="font-bold">{row.name}</span></div> }, { key: 'type', header: 'الصفة', cell: (row) => <span className="rounded-md bg-muted px-2.5 py-1 text-xs font-semibold">{row.type}</span> }, { key: 'id', header: 'المعرّف', cell: (row) => <span className="font-mono text-xs text-muted-foreground">#{row.id}</span> }]} renderFields={({ register, formState: { errors } }) => <><FormField label="اسم المدرس" name="name" required error={errors.name}><Input id="name" placeholder="مثال: د. أحمد محمد" {...register('name')} /></FormField><FormField label="الصفة الأكاديمية" name="type" required error={errors.type}><Select id="type" {...register('type')}>{types.map((type) => <option key={type} value={type}>{type}</option>)}</Select></FormField></>} /></div>
}
