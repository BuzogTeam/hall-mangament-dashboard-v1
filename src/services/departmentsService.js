import { deleteRow, insertRow, selectRows, updateRow } from './baseService'

export const departmentsService = {
  list: () => selectRows('departments', 'id, title, abbreviation, num_levels, created_at', (query) => query.order('title')),
  create: (payload) => insertRow('departments', {
    title: payload.title.trim(),
    abbreviation: payload.abbreviation.trim().toUpperCase(),
    num_levels: Number(payload.num_levels),
  }, 'id, title, abbreviation, num_levels, created_at'),
  update: (id, payload) => updateRow('departments', id, {
    title: payload.title.trim(),
    abbreviation: payload.abbreviation.trim().toUpperCase(),
    num_levels: Number(payload.num_levels),
  }, 'id, title, abbreviation, num_levels, created_at'),
  remove: (id) => deleteRow('departments', id),
}
