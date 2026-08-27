import { deleteRow, insertRow, selectRows, updateRow } from './baseService'

export const buildingsService = {
  list: () => selectRows('buildings', 'id, title, created_at', (query) => query.order('id', { ascending: true })),
  create: (payload) => insertRow('buildings', { title: payload.title.trim() }, 'id, title, created_at'),
  update: (id, payload) => updateRow('buildings', id, { title: payload.title.trim() }, 'id, title, created_at'),
  remove: (id) => deleteRow('buildings', id),
}
