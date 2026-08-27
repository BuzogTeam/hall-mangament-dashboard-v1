import { deleteRow, insertRow, selectRows, updateRow } from './baseService'

export const instructorsService = {
  list: () => selectRows('instructors', 'id, name, type, created_at', (query) => query.order('name')),
  create: (payload) => insertRow('instructors', { name: payload.name.trim(), type: payload.type }, 'id, name, type, created_at'),
  update: (id, payload) => updateRow('instructors', id, { name: payload.name.trim(), type: payload.type }, 'id, name, type, created_at'),
  remove: (id) => deleteRow('instructors', id),
}
