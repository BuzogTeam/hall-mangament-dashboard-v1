import { deleteRow, insertRow, selectRows, updateRow } from './baseService'

export const levelsService = {
  list: () => selectRows('levels', 'id, title, created_at', (query) => query.order('id')),
  create: (payload) => insertRow('levels', { title: payload.title.trim() }, 'id, title, created_at'),
  update: (id, payload) => updateRow('levels', id, { title: payload.title.trim() }, 'id, title, created_at'),
  remove: (id) => deleteRow('levels', id),
}
