import { supabase } from '../lib/supabase'
import { rangesOverlap, getErrorMessage } from '../lib/utils'
import { deleteRow, insertRow, selectRows, updateRow } from './baseService'

export const LECTURE_SELECT = [
  'id', 'created_at', 'day_of_week', 'start_at', 'end_at', 'subject_id', 'hall_id', 'instructor_id', 'canceled', 'groups', 'batch_id', 'updated_at',
  'subject:subjects!lectures_subject_id_fkey(id,title,english_title,type,parent_id)',
  'hall:halls!lectures_hall_id_fkey(id,title,building_id,floor,type,booking,building:buildings!halls_building_id_fkey(id,title))',
  'instructor:instructors!lectures_instructor_id_fkey(id,name,type)',
  'batch:batches!lectures_batch_id_fkey(id,department_id,level_id,department_abbr,department:departments!departments_levels_department_id_fkey(id,title,abbreviation),level:levels!departments_levels_level_id_fkey(id,title))',
].join(',')

export const lecturesService = {
  list: () => selectRows('lectures', LECTURE_SELECT, (query) => query.order('day_of_week').order('start_at')),

  async findConflicts(payload, excludeId = null) {
    // Prefer the SECURITY DEFINER database function when functions.sql is installed.
    // The fallback keeps the dashboard usable during a staged migration.
    const { data: rpcRows, error: rpcError } = await supabase.rpc('find_lecture_conflicts_v2', {
      p_day_of_week: payload.day_of_week,
      p_start_at: payload.start_at,
      p_end_at: payload.end_at,
      p_hall_id: Number(payload.hall_id),
      p_instructor_id: Number(payload.instructor_id),
      p_batch_id: Number(payload.batch_id),
      p_groups: payload.groups || [],
      p_exclude_id: excludeId ? Number(excludeId) : null,
    })
    if (!rpcError) {
      const rows = rpcRows || []
      return {
        hall: rows.filter((row) => row.conflict_type === 'hall'),
        instructor: rows.filter((row) => row.conflict_type === 'instructor'),
        batch: rows.filter((row) => row.conflict_type === 'batch'),
        all: rows,
      }
    }

    // Only fall back when the function has not been deployed yet. Permission,
    // validation, and database errors must not be hidden by a client-side query.
    const functionMissing = rpcError.code === 'PGRST202' || /function .* does not exist|could not find the function/i.test(rpcError.message || '')
    if (!functionMissing) throw rpcError

    let query = supabase
      .from('lectures')
      .select('id, day_of_week, start_at, end_at, hall_id, instructor_id, batch_id, canceled, subject:subjects!lectures_subject_id_fkey(title), hall:halls!lectures_hall_id_fkey(title), instructor:instructors!lectures_instructor_id_fkey(name), batch:batches!lectures_batch_id_fkey(id,department_abbr,department:departments!departments_levels_department_id_fkey(title),level:levels!departments_levels_level_id_fkey(title))')
      .eq('day_of_week', payload.day_of_week)
      .eq('canceled', false)
    if (excludeId) query = query.neq('id', excludeId)
    const { data, error } = await query
    if (error) throw error
    const conflicts = (data || []).filter((lecture) => rangesOverlap(payload.start_at, payload.end_at, lecture.start_at, lecture.end_at))
    return {
      hall: conflicts.filter((lecture) => Number(lecture.hall_id) === Number(payload.hall_id)),
      instructor: conflicts.filter((lecture) => Number(lecture.instructor_id) === Number(payload.instructor_id)),
      batch: conflicts.filter((lecture) => Number(lecture.batch_id) === Number(payload.batch_id)),
      all: conflicts,
    }
  },

  async saveWithConflictCheck(payload, id = null) {
    // The RPC performs validation, conflict detection, locking, and the write in
    // one transaction. This replaces the old check-then-insert/update race window.
    const { data, error } = await supabase.rpc('save_lecture_atomic', {
      p_lecture_id: id ? Number(id) : null,
      p_payload: payload,
    })
    if (!error) return data

    // Keep an already-deployed installation usable while the incremental migration
    // is being applied. This fallback is not atomic; production must run the RPC.
    const missing = error.code === 'PGRST202' || /function .*save_lecture_atomic.*not found|could not find the function/i.test(error.message || '')
    if (!missing) throw error
    const conflicts = await lecturesService.findConflicts(payload, id)
    const messages = []
    if (conflicts.hall.length) messages.push('القاعة محجوزة في هذا الوقت')
    if (conflicts.instructor.length) messages.push('المدرس مرتبط بمحاضرة أخرى في هذا الوقت')
    if (conflicts.batch.length) messages.push('الدفعة لديها محاضرة أخرى في هذا الوقت')
    if (messages.length) throw new Error(messages.join('، '))
    return id ? updateRow('lectures', id, payload, LECTURE_SELECT) : insertRow('lectures', payload, LECTURE_SELECT)
  },

  create: (payload) => lecturesService.saveWithConflictCheck(payload),
  update: (id, payload) => lecturesService.saveWithConflictCheck(payload, id),
  async toggleCanceled(id, canceled, reason = '') {
    const { data, error } = await supabase.rpc('set_lecture_canceled_with_reason', {
      p_lecture_id: Number(id),
      p_canceled: Boolean(canceled),
      p_reason: reason?.trim() || null,
    })
    if (!error) return data
    const missing = error.code === 'PGRST202' || /function .*set_lecture_canceled_with_reason.*not found|could not find the function/i.test(error.message || '')
    if (!missing) throw error
    // Backward-compatible fallback. The deployed two-argument RPC still checks
    // cancel permission and reactivation conflicts; history reasons are available
    // after schedule_hardening.sql is applied.
    const fallback = await supabase.rpc('set_lecture_canceled', {
      p_lecture_id: Number(id),
      p_canceled: Boolean(canceled),
    })
    if (fallback.error) throw fallback.error
    return fallback.data
  },
  remove: (id) => deleteRow('lectures', id),

  async getSchedule() {
    return lecturesService.list()
  },

  conflictMessage(error) {
    if (error?.code !== 'LECTURE_CONFLICT') return getErrorMessage(error)
    const parts = []
    if (error.conflicts?.hall?.length) parts.push('تعارض القاعة')
    if (error.conflicts?.instructor?.length) parts.push('تعارض المدرس')
    if (error.conflicts?.batch?.length) parts.push('تعارض الدفعة')
    return `${error.message}${parts.length ? ` (${parts.join('، ')})` : ''}`
  },
}
