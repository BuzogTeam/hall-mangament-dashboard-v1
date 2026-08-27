import { useEffect } from 'react'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { Button } from '../ui/button'
import { Dialog, DialogClose, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '../ui/dialog'
import { getErrorMessage } from '../../lib/utils'

export function EntityDialog({ open, onOpenChange, title, description, schema, defaultValues, onSubmit, loading = false, renderFields, submitLabel = 'حفظ التغييرات', serverError }) {
  const form = useForm({ resolver: schema ? zodResolver(schema) : undefined, defaultValues, mode: 'onTouched' })
  const { reset, handleSubmit, formState } = form
  useEffect(() => { if (open) reset(defaultValues) }, [open, defaultValues, reset])
  const submit = async (values) => {
    try {
      await onSubmit(values, form)
    } catch (error) {
      // Parent mutations expose the error through serverError; avoid an unhandled
      // rejection bubbling out of react-hook-form's submit handler.
      console.error(error)
    }
  }
  return <Dialog open={open} onOpenChange={onOpenChange}><DialogContent><DialogClose onClick={() => onOpenChange?.(false)} /><DialogHeader><DialogTitle>{title}</DialogTitle>{description ? <DialogDescription>{description}</DialogDescription> : null}</DialogHeader>{serverError ? <div className="mb-4 rounded-xl border border-rose-200 bg-rose-50 px-3 py-2 text-sm leading-6 text-rose-700 dark:border-rose-900 dark:bg-rose-950/25 dark:text-rose-300">{getErrorMessage(serverError)}</div> : null}<form onSubmit={handleSubmit(submit)} noValidate><div className="space-y-4">{renderFields(form)}</div><DialogFooter><Button type="button" variant="outline" onClick={() => onOpenChange?.(false)} disabled={loading}>إلغاء</Button><Button type="submit" disabled={loading || formState.isSubmitting}>{loading || formState.isSubmitting ? 'جارٍ الحفظ…' : submitLabel}</Button></DialogFooter></form></DialogContent></Dialog>
}
