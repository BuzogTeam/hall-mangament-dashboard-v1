import { supabase } from '../lib/supabase'
import { selectRows } from './baseService'

export const departmentLevelsService = {
  list: () => selectRows('department_levels', 'department_id,level_id,is_active', (query) => query.eq('is_active', true).order('department_id').order('level_id')),
  async set(departmentId, levelIds) {
    const { error } = await supabase.rpc('admin_set_department_levels', { p_department_id: Number(departmentId), p_level_ids: levelIds.map((id) => Number(id)) })
    if (error) throw error
  },
}
