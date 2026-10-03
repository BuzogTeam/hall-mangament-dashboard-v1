import { useMemo } from 'react'
import { useQuery } from '@tanstack/react-query'
import { BookOpen } from 'lucide-react'
import { z } from 'zod'
import { CrudResourcePage } from '../../components/common/CrudResourcePage'
import { FormField } from '../../components/common/FormField'
import { SearchableSelectField } from '../../components/common/SearchableSelect'
import { Input } from '../../components/ui/input'
import { Select } from '../../components/ui/select'
import { subjectsService } from '../../services/subjectsService'
import { metadataService } from '../../services/metadataService'
import { ENUM_OPTIONS } from '../../lib/utils'
import { usePageTitle } from '../../hooks/usePageTitle'

const schema = z.object({ title: z.string().trim().min(2, 'اسم المادة مطلوب'), english_title: z.string().optional(), type: z.string().min(1, 'اختر نوع المادة'), parent_id: z.string().optional() })

export function Subjects() {
  usePageTitle('المواد الدراسية')
  const subjects = useQuery({ queryKey: ['subjects', 'parents'], queryFn: subjectsService.list })
  const metadata = useQuery({ queryKey: ['metadata'], queryFn: metadataService.getOptions })
  const subjectTypes = metadata.data?.subjectTypes?.length ? metadata.data.subjectTypes : ENUM_OPTIONS.subjectTypes
  const parentOptions = useMemo(() => (subjects.data || []).filter((item) => !item.parent_id), [subjects.data])
  return <div className="page-enter"><CrudResourcePage title="المواد الدراسية" description="إدارة المواد النظرية والعملية وربط المواد التابعة بمادتها الرئيسية." icon={BookOpen} resource="subjects" queryKey="subjects" service={subjectsService} schema={schema} defaultValues={{ title: '', english_title: '', type: subjectTypes[0], parent_id: '' }} searchPlaceholder="ابحث باسم المادة بالعربية أو الإنجليزية…" searchFields={[(row) => row.title, (row) => row.english_title, (row) => row.type]} columns={[{ key: 'title', header: 'المادة', cell: (row) => <div><p className="font-bold">{row.title}</p>{row.english_title ? <p className="mt-0.5 text-xs text-muted-foreground" dir="ltr">{row.english_title}</p> : null}</div> }, { key: 'type', header: 'النوع', cell: (row) => <span className="rounded-md bg-primary/10 px-2 py-1 text-xs font-semibold text-primary">{row.type}</span> }, { key: 'parent_id', header: 'المادة الرئيسية', cell: (row) => row.parent_id ? (parentOptions.find((parent) => parent.id === row.parent_id)?.title || `#${row.parent_id}`) : <span className="text-muted-foreground">مادة رئيسية</span> }, { key: 'id', header: 'المعرّف', cell: (row) => <span className="font-mono text-xs text-muted-foreground">#{row.id}</span> }]} renderFields={({ register, formState: { errors }, watch, setValue }) => <><FormField label="اسم المادة" name="title" required error={errors.title}><Input id="title" placeholder="مثال: قواعد البيانات" {...register('title')} /></FormField><FormField label="الاسم باللغة الإنجليزية" name="english_title" error={errors.english_title}><Input id="english_title" dir="ltr" placeholder="Database Systems" {...register('english_title')} /></FormField><div className="grid gap-4 sm:grid-cols-2"><FormField label="نوع المادة" name="type" required error={errors.type}><Select id="type" {...register('type')}>{subjectTypes.map((type) => <option key={type} value={type}>{type}</option>)}</Select></FormField><FormField label="المادة الرئيسية" name="parent_id" error={errors.parent_id} hint="اختياري للجزء العملي أو التمارين."><SearchableSelectField name="parent_id" register={register} watch={watch} setValue={setValue} options={parentOptions.map((item) => ({ value: item.id, label: item.title, searchText: `${item.title} ${item.id}` }))} placeholder="اكتب اسم المادة الرئيسية…" searchPlaceholder="ابحث في المواد الرئيسية…" /></FormField></div></>} mapFormValues={(row) => ({ title: row.title || '', english_title: row.english_title || '', type: row.type || subjectTypes[0], parent_id: row.parent_id ? String(row.parent_id) : '' })} mapSubmitValues={(values, editing) => ({ ...values, parent_id: values.parent_id && Number(values.parent_id) !== Number(editing?.id) ? Number(values.parent_id) : null })} deleteDescription="لا يمكن حذف مادة مرتبطة بمحاضرات أو مواد تابعة قبل معالجة العلاقات." /></div>
}
