import { supabase } from '../lib/supabase'
import { deleteRow, selectRows } from './baseService'

export const RESERVATION_SELECT = 'id,hall_id,reservation_date,day_of_week,department_id,level_id,start_at,end_at,status,reason,notes,created_by,updated_by,created_at,updated_at,hall:halls!hall_reservations_hall_id_fkey(id,title,booking,building:buildings!halls_building_id_fkey(id,title)),department:departments!hall_reservations_department_id_fkey(id,title,abbreviation),level:levels!hall_reservations_level_id_fkey(id,title)'
const LEGACY_RESERVATION_SELECT = 'id,hall_id,reservation_date,day_of_week,start_at,end_at,status,reason,notes,created_by,updated_by,created_at,updated_at,hall:halls!hall_reservations_hall_id_fkey(id,title,booking,building:buildings!halls_building_id_fkey(id,title))'

function scopeColumnsMissing(error) {
  return error?.code === 'PGRST204' || error?.code === 'PGRST200' || /department_id|level_id|hall_reservations_department_id_fkey|hall_reservations_level_id_fkey/i.test(error?.message || '')
}

export const reservationsService = {
  async list() {
    const primary = await supabase.from('hall_reservations').select(RESERVATION_SELECT).order('status').order('reservation_date').order('day_of_week').order('start_at')
    if (!primary.error) return primary.data || []
    // Keep existing global-role clients usable until the incremental scope
    // migration has been applied and PostgREST has refreshed its schema cache.
    if (!scopeColumnsMissing(primary.error)) throw primary.error
    return selectRows('hall_reservations', LEGACY_RESERVATION_SELECT, (query) => query.order('status').order('day_of_week').order('start_at'))
  },
  async save(payload, id = null) {
    const { data, error } = await supabase.rpc('save_hall_reservation', { p_reservation_id: id ? Number(id) : null, p_payload: payload })
    if (error) throw error
    return data
  },
  async findConflicts(payload, id = null) {
    const { data, error } = await supabase.rpc('find_hall_reservation_conflicts_scoped', {
      p_hall_id: Number(payload.hall_id),
      p_reservation_date: payload.reservation_date || null,
      p_day_of_week: payload.day_of_week || null,
      p_start_at: payload.start_at,
      p_end_at: payload.end_at,
      p_department_id: payload.department_id ? Number(payload.department_id) : null,
      p_level_id: payload.level_id ? Number(payload.level_id) : null,
      p_exclude_id: id ? Number(id) : null,
    })
    if (error) throw error
    return data || []
  }, 
  async setStatus(id, status, reason = '') {
    const { data, error } = await supabase.rpc('set_hall_reservation_status', { p_reservation_id: Number(id), p_status: status, p_reason: reason?.trim() || null })
    if (error) throw error
    return data
  },
  remove: (id) => deleteRow('hall_reservations', id),
}
