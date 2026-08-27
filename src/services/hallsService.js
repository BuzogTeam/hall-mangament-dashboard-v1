import { deleteRow, insertRow, selectRows, updateRow } from './baseService'

const HALL_SELECT = 'id, title, building_id, floor, type, booking, created_at, building:buildings!halls_building_id_fkey(id,title)'

export const hallsService = {
  list: () => selectRows('halls', HALL_SELECT, (query) => query.order('building_id').order('title')),
  create: (payload) => insertRow('halls', {
    title: payload.title.trim(),
    building_id: Number(payload.building_id),
    floor: payload.floor,
    type: payload.type,
    booking: Boolean(payload.booking),
  }, HALL_SELECT),
  update: (id, payload) => updateRow('halls', id, {
    title: payload.title.trim(),
    building_id: Number(payload.building_id),
    floor: payload.floor,
    type: payload.type,
    booking: Boolean(payload.booking),
  }, HALL_SELECT),
  remove: (id) => deleteRow('halls', id),
}
