import { deleteRow, insertRow, selectRows, updateRow } from './baseService'

const BATCH_SELECT = 'id, department_id, level_id, department_abbr, created_at, department:departments!departments_levels_department_id_fkey(id,title,abbreviation), level:levels!departments_levels_level_id_fkey(id,title)'

export const batchesService = {
  list: () => selectRows('batches', BATCH_SELECT, (query) => query.order('department_abbr').order('level_id')),
  create: (payload) => insertRow('batches', {
    department_id: Number(payload.department_id),
    level_id: payload.level_id ? Number(payload.level_id) : null,
    department_abbr: payload.department_abbr,
  }, BATCH_SELECT),
  update: (id, payload) => updateRow('batches', id, {
    department_id: Number(payload.department_id),
    level_id: payload.level_id ? Number(payload.level_id) : null,
    department_abbr: payload.department_abbr,
  }, BATCH_SELECT),
  remove: (id) => deleteRow('batches', id),
}
