import { supabase } from '../lib/supabase'
import { getErrorMessage } from '../lib/utils'

function noReturnedRowError(operation) {
  const error = new Error(`لم تُرجع عملية ${operation} أي سجل. تحقق من وجود السجل وسياسات RLS للقراءة والكتابة.`)
  error.code = 'PGRST_NO_RETURNED_ROW'
  return error
}

export async function selectRows(table, select = '*', configure) {
  let query = supabase.from(table).select(select)
  if (configure) query = configure(query)
  const { data, error } = await query
  if (error) throw error
  return data || []
}

export async function selectOne(table, select = '*', configure) {
  let query = supabase.from(table).select(select)
  if (configure) query = configure(query)
  const { data, error } = await query.maybeSingle()
  if (error) throw error
  return data
}

export async function insertRow(table, payload, select = '*') {
  const { data, error } = await supabase.from(table).insert(payload).select(select).maybeSingle()
  if (error) throw error
  if (!data) throw noReturnedRowError('الإضافة')
  return data
}

export async function updateRow(table, id, payload, select = '*') {
  const { data, error } = await supabase.from(table).update(payload).eq('id', id).select(select).maybeSingle()
  if (error) throw error
  if (!data) throw noReturnedRowError('التعديل')
  return data
}

export async function deleteRow(table, id) {
  // DELETE without RETURNING can report success even when RLS filtered the row
  // and nothing was deleted. Ask PostgREST to return the id and verify it.
  const { data, error } = await supabase.from(table).delete().eq('id', id).select('id').maybeSingle()
  if (error) throw error
  if (!data) throw noReturnedRowError('الحذف')
}

export async function countRows(table, configure) {
  let query = supabase.from(table).select('id', { count: 'exact', head: true })
  if (configure) query = configure(query)
  const { count, error } = await query
  if (error) throw error
  return count || 0
}

export function explainDatabaseError(error) {
  const message = getErrorMessage(error)
  if (/record ["']?new["']? has no field ["']?updated_at["']?/i.test(message)) {
    return 'يوجد Trigger قديم يحاول تحديث updated_at في جدول لا يحتوي هذا العمود. شغّل migration إصلاح Triggers الخاصة بالجداول الأكاديمية ثم أعد المحاولة.'
  }
  if (error?.code === '42501' || /permission|not authorized|row-level security|row-level security policy|JWT/i.test(message)) {
    return 'ليست لديك صلاحية لتنفيذ هذه العملية أو أن سياسة RLS لا تسمح بها. تأكد من تشغيل Migration صلاحيات الجدول للمستخدمين المسجلين.'
  }
  if (error?.code === 'PGRST_NO_RETURNED_ROW' || /Cannot coerce the result to a single JSON object|PGRST116|406/.test(message)) {
    return 'لم تُرجع قاعدة البيانات سجلًا للعملية. غالبًا يوجد تعارض في RLS أو لا تملك العملية صلاحية SELECT/UPDATE/DELETE على هذا السجل.'
  }
  if (/foreign key|violates foreign key|referential integrity/i.test(message)) {
    return 'لا يمكن تنفيذ العملية لأن العنصر مرتبط ببيانات أخرى. عالج العلاقات المرتبطة أولاً.'
  }
  if (/duplicate|unique/i.test(message)) {
    return 'القيمة موجودة مسبقًا. استخدم قيمة مختلفة.'
  }
  if (/profiles|schema cache|does not exist/i.test(message)) {
    return 'لم يتم تجهيز جداول النظام الإضافية بعد. طبّق ملفات SQL داخل مجلد supabase أولاً.'
  }
  return message || 'تعذر تنفيذ العملية.'
}
