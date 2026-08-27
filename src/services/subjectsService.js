import { deleteRow, insertRow, selectRows, updateRow } from './baseService'

const SUBJECT_SELECT = 'id, title, english_title, type, parent_id, created_at'

export const subjectsService = {
  list: () => selectRows('subjects', SUBJECT_SELECT, (query) => query.order('title')),
  create: (payload) => insertRow('subjects', {
    title: payload.title.trim(),
    english_title: payload.english_title?.trim() || null,
    type: payload.type,
    parent_id: payload.parent_id ? Number(payload.parent_id) : null,
  }, SUBJECT_SELECT),
  update: (id, payload) => updateRow('subjects', id, {
    title: payload.title.trim(),
    english_title: payload.english_title?.trim() || null,
    type: payload.type,
    parent_id: payload.parent_id ? Number(payload.parent_id) : null,
  }, SUBJECT_SELECT),
  remove: (id) => deleteRow('subjects', id),
}
