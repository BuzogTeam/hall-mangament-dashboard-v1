import { getDayLabel } from '../lib/utils'
import { selectRows } from './baseService'
import { LECTURE_SELECT } from './lecturesService'

export const reportsService = {
  async getReport() {
    const lectures = await selectRows('lectures', LECTURE_SELECT, (query) => query.order('day_of_week').order('start_at'))
    const activeLectures = lectures.filter((lecture) => !lecture.canceled)
    const cancelledLectures = lectures.filter((lecture) => lecture.canceled)
    const groupCount = (items, key, label) => {
      const map = new Map()
      items.forEach((item) => {
        const value = key(item) || 'غير محدد'
        const current = map.get(value) || { name: value, value: 0, label: label?.(item) || value }
        current.value += 1
        map.set(value, current)
      })
      return [...map.values()].sort((a, b) => b.value - a.value)
    }
    return {
      lectures,
      total: lectures.length,
      active: activeLectures.length,
      canceled: cancelledLectures.length,
      byDay: groupCount(activeLectures, (item) => getDayLabel(item.day_of_week)),
      byHall: groupCount(activeLectures, (item) => item.hall?.title, (item) => item.hall?.building?.title ? `${item.hall.title} — ${item.hall.building.title}` : item.hall?.title),
      byDepartment: groupCount(activeLectures, (item) => item.batch?.department?.abbreviation || item.batch?.department_abbr, (item) => item.batch?.department?.title),
      byInstructor: groupCount(activeLectures, (item) => item.instructor?.name),
      canceledRows: cancelledLectures,
    }
  },
}
