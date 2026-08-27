import { supabase } from '../lib/supabase'
import { deleteRow, selectRows } from './baseService'

export const RESERVATION_SELECT = 'id,hall_id,day_of_week,start_at,end_at,status,reason,notes,created_by,updated_by,created_at,updated_at,hall:halls!hall_reservations_hall_id_fkey(id,title,booking,building:buildings!halls_building_id_fkey(id,title))'

export const reservationsService = {
  list: () => selectRows('hall_reservations', RESERVATION_SELECT, (query) => query.order('status').order('day_of_week').order('start_at')),
  async save(payload, id = null) {
    const { data, error } = await supabase.rpc('save_hall_reservation', { p_reservation_id: id ? Number(id) : null, p_payload: payload })
    if (error) throw error
    return data
  },
  async setStatus(id, status, reason = '') {
    const { data, error } = await supabase.rpc('set_hall_reservation_status', { p_reservation_id: Number(id), p_status: status, p_reason: reason?.trim() || null })
    if (error) throw error
    return data
  },
  remove: (id) => deleteRow('hall_reservations', id),
}
