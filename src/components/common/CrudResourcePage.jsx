import { useEffect, useMemo, useRef, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { Pencil, Plus, Trash2 } from 'lucide-react'
import { useAuth } from '../../context/AuthContext'
import { can } from '../../lib/permissions'
import { includesText } from '../../lib/utils'
import { explainDatabaseError } from '../../services/baseService'
import { Button } from '../ui/button'
import { Card } from '../ui/card'
import { EntityDialog } from './EntityDialog'
import { ConfirmDialog } from './ConfirmDialog'
import { DataTable } from './DataTable'
import { ErrorState } from './ErrorState'
import { PageHeader } from './PageHeader'
import { Pagination } from './Pagination'
import { SearchInput } from './SearchInput'

const PAGE_SIZE = 10

export function CrudResourcePage({
  title,
  description,
  icon,
  resource,
  queryKey,
  service,
  columns,
  schema,
  defaultValues,
  renderFields,
  searchPlaceholder = 'البحث في السجلات…',
  searchFields = [],
  mapFormValues = (item) => item,
  mapSubmitValues = (values) => values,
  emptyTitle = 'لا توجد سجلات',
  emptyDescription = 'ابدأ بإضافة أول سجل إلى قاعدة البيانات.',
  renderToolbar,
  filterData,
  extraActions,
  showDelete = true,
  deleteDescription,
  deleteLabel = 'حذف السجل',
  initialEditId = null,
}) {
  const { profile } = useAuth()
  const queryClient = useQueryClient()
  const [search, setSearch] = useState('')
  const [filters, setFilters] = useState({})
  const [page, setPage] = useState(1)
  const [dialogOpen, setDialogOpen] = useState(false)
  const [editing, setEditing] = useState(null)
  const [deleting, setDeleting] = useState(null)
  const [serverError, setServerError] = useState(null)
  const handledInitialEdit = useRef(null)

  const query = useQuery({ queryKey: [queryKey], queryFn: service.list })
  const saveMutation = useMutation({
    mutationFn: ({ id, values }) => id ? service.update(id, values) : service.create(values),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: [queryKey] })
      queryClient.invalidateQueries({ queryKey: ['dashboard'] })
      queryClient.invalidateQueries({ queryKey: ['reports'] })
      queryClient.invalidateQueries({ queryKey: ['metadata'] })
      queryClient.invalidateQueries({ queryKey: ['notifications'] })
      setDialogOpen(false)
      setEditing(null)
      setServerError(null)
      toast.success(editing ? 'تم تحديث السجل بنجاح' : 'تمت إضافة السجل بنجاح')
    },
    onError: (error) => setServerError(new Error(explainDatabaseError(error))),
  })
  const deleteMutation = useMutation({
    mutationFn: (id) => service.remove(id),
    onSuccess: (_data, deletedId) => {
      // Remove the confirmed row immediately. The background refetch keeps the
      // cache consistent with Supabase and prevents the table from waiting for
      // another mutation before repainting.
      queryClient.setQueryData([queryKey], (current) => Array.isArray(current) ? current.filter((row) => String(row.id) !== String(deletedId)) : current)
      queryClient.invalidateQueries({ queryKey: [queryKey] })
      queryClient.invalidateQueries({ queryKey: ['dashboard'] })
      queryClient.invalidateQueries({ queryKey: ['reports'] })
      queryClient.invalidateQueries({ queryKey: ['metadata'] })
      queryClient.invalidateQueries({ queryKey: ['notifications'] })
      setDeleting(null)
      toast.success('تم حذف السجل بنجاح')
    },
    onError: (error) => {
      setServerError(new Error(explainDatabaseError(error)))
      toast.error(explainDatabaseError(error))
    },
  })

  useEffect(() => { setPage(1) }, [search, filters])

  const filteredData = useMemo(() => {
    let rows = query.data || []
    if (search) rows = rows.filter((row) => searchFields.some((field) => {
      const value = typeof field === 'function' ? field(row) : row[field]
      if (Array.isArray(value)) return includesText(value.join(' '), search)
      return includesText(value, search)
    }))
    if (filterData) rows = filterData(rows, filters)
    return rows
  }, [query.data, search, searchFields, filterData, filters])

  const pageCount = Math.max(1, Math.ceil(filteredData.length / PAGE_SIZE))
  useEffect(() => { setPage((current) => Math.min(current, pageCount)) }, [pageCount])
  const visibleData = filteredData.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE)
  const mayCreate = can(profile, `${resource}.create`)
  const mayUpdate = can(profile, `${resource}.update`)
  const mayDelete = can(profile, `${resource}.delete`)

  useEffect(() => {
    if (!initialEditId || !query.isSuccess || !mayUpdate || handledInitialEdit.current === String(initialEditId)) return
    const item = (query.data || []).find((row) => String(row.id) === String(initialEditId))
    if (item) {
      setEditing(item)
      setServerError(null)
      setDialogOpen(true)
    }
    handledInitialEdit.current = String(initialEditId)
  }, [initialEditId, mayUpdate, query.data, query.isSuccess])

  const openCreate = () => { setEditing(null); setServerError(null); setDialogOpen(true) }
  const openEdit = (item) => { setEditing(item); setServerError(null); setDialogOpen(true) }
  const handleSubmit = async (values) => {
    setServerError(null)
    try {
      await saveMutation.mutateAsync({ id: editing?.id, values: mapSubmitValues(values, editing) })
    } catch (error) {
      // The mutation owns the visible error state. Re-throwing would result in an unhandled promise in RHF.
    }
  }
  const handleDelete = async () => {
    try { await deleteMutation.mutateAsync(deleting.id) } catch (error) { setServerError(new Error(explainDatabaseError(error))) }
  }

  if (!can(profile, `${resource}.view`)) {
    return <div className="mx-auto max-w-2xl py-12"><ErrorState title="لا تملك صلاحية الوصول" error="هذا القسم متاح لأدوار محددة فقط." /></div>
  }

  return <>
    <PageHeader title={title} description={description} icon={icon} actionLabel={mayCreate ? 'إضافة جديد' : undefined} onAction={openCreate} actionPermission={mayCreate}>
      {extraActions?.({ data: query.data || [], filters, setFilters })}
    </PageHeader>
    {query.isError ? <ErrorState error={query.error} onRetry={() => query.refetch()} /> : <Card className="overflow-hidden">
      <div className="flex flex-col gap-3 border-b border-border p-4 lg:flex-row lg:items-center"><SearchInput value={search} onChange={setSearch} placeholder={searchPlaceholder} className="w-full lg:max-w-sm" />{renderToolbar?.({ filters, setFilters, data: query.data || [] })}</div>
      {serverError && !dialogOpen ? <div className="mx-4 mt-4 rounded-xl border border-rose-200 bg-rose-50 px-4 py-3 text-sm text-rose-700 dark:border-rose-900 dark:bg-rose-950/25 dark:text-rose-300">{serverError.message}</div> : null}
      <DataTable columns={columns} data={visibleData} loading={query.isLoading} emptyTitle={search || Object.keys(filters).some((key) => filters[key]) ? 'لا توجد نتائج مطابقة' : emptyTitle} emptyDescription={search || Object.keys(filters).some((key) => filters[key]) ? 'جرّب تغيير عبارة البحث أو الفلاتر.' : emptyDescription} emptyActionLabel={mayCreate ? 'إضافة السجل الأول' : undefined} onEmptyAction={openCreate} actions={(row) => <div className="flex items-center gap-1">{mayUpdate ? <Button variant="ghost" size="icon" className="h-8 w-8 text-muted-foreground hover:text-primary" onClick={() => openEdit(row)} title="تعديل"><Pencil className="h-4 w-4" /></Button> : null}{showDelete && mayDelete ? <Button variant="ghost" size="icon" className="h-8 w-8 text-muted-foreground hover:text-destructive" onClick={() => setDeleting(row)} title="حذف"><Trash2 className="h-4 w-4" /></Button> : null}{extraActions?.({ row, openEdit, queryClient })}</div>} />
      {!query.isLoading && filteredData.length > 0 ? <Pagination page={page} pageCount={pageCount} onPageChange={setPage} total={filteredData.length} pageSize={PAGE_SIZE} /> : null}
    </Card>}
    <EntityDialog open={dialogOpen} onOpenChange={(open) => { setDialogOpen(open); if (!open) setServerError(null) }} title={editing ? `تعديل ${title}` : `إضافة ${title}`} description={editing ? 'حدّث البيانات ثم احفظ التغييرات.' : 'أدخل البيانات الأساسية ثم احفظ السجل في Supabase.'} schema={schema} defaultValues={editing ? mapFormValues(editing) : defaultValues} onSubmit={handleSubmit} loading={saveMutation.isPending} renderFields={renderFields} serverError={serverError} submitLabel={editing ? 'حفظ التعديلات' : 'إضافة السجل'} />
    <ConfirmDialog open={Boolean(deleting)} onOpenChange={(open) => !open && setDeleting(null)} title={`حذف ${title}`} description={deleteDescription || 'سيتم حذف السجل نهائيًا من قاعدة البيانات. تأكد من عدم وجود علاقات مرتبطة به.'} confirmLabel={deleteLabel} loading={deleteMutation.isPending} onConfirm={handleDelete} />
  </>
}
