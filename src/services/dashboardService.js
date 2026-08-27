import { supabase } from '../lib/supabase'
import { getLectureStatus, getTodayDbValue, getDayLabel, getStatusLabel, isReservationActiveNow } from '../lib/utils'
import { selectRows } from './baseService'
import { LECTURE_SELECT } from './lecturesService'

async function count(table) {
  const { count: total, error } = await supabase.from(table).select('id', { count: 'exact', head: true })
  if (error) throw error
  return total || 0
}

async function listOptionalReservations() {
  const { data, error } = await supabase.from('hall_reservations').select('id,hall_id,day_of_week,start_at,end_at,status')
  if (error) {
    const missing = error.code === 'PGRST205' || /hall_reservations.*schema cache|does not exist/i.test(error.message || '')
    if (missing) return []
    throw error
  }
  return data || []
}

export const dashboardService = {
  async getOverview() {
    const [buildingCount, hallCount, departmentCount, subjectCount, instructorCount, lectureCount, halls, lectures, subjects, reservations] = await Promise.all([
      count('buildings'), count('halls'), count('departments'), count('subjects'), count('instructors'), count('lectures'),
      selectRows('halls', 'id,title,booking,type,building_id,building:buildings!halls_building_id_fkey(id,title)'),
      selectRows('lectures', LECTURE_SELECT, (query) => query.order('updated_at', { ascending: false })),
      selectRows('subjects', 'id,type'),
      listOptionalReservations(),
    ])
    const todayKey = getTodayDbValue()
    const todaysLectures = lectures.filter((lecture) => lecture.day_of_week === todayKey)
    const unavailableHallIds = new Set(halls.filter((hall) => hall.booking).map((hall) => hall.id))
    const reservedHallIds = new Set(reservations.filter((reservation) => isReservationActiveNow(reservation)).map((reservation) => reservation.hall_id))
    const occupiedHallIds = new Set(
      halls.filter((hall) => !unavailableHallIds.has(hall.id) && !reservedHallIds.has(hall.id) && todaysLectures.some((lecture) => lecture.hall_id === hall.id && getLectureStatus(lecture) === 'live')).map((hall) => hall.id),
    )
    const recent = [
      ...lectures.map((item) => ({ ...item, activityType: 'lecture', activityDate: item.updated_at || item.created_at })),
      ...halls.map((item) => ({ ...item, activityType: 'hall', activityDate: item.created_at })),
    ].sort((a, b) => new Date(b.activityDate) - new Date(a.activityDate)).slice(0, 6)

    const byDay = new Map()
    lectures.forEach((lecture) => {
      const key = lecture.day_of_week
      byDay.set(key, (byDay.get(key) || 0) + 1)
    })

    return {
      stats: {
        buildings: buildingCount, halls: hallCount, departments: departmentCount, subjects: subjectCount,
        instructors: instructorCount, lectures: lectureCount, todayLectures: todaysLectures.length,
        occupiedHalls: occupiedHallIds.size, reservedHalls: reservedHallIds.size, unavailableHalls: unavailableHallIds.size,
        availableHalls: Math.max(0, halls.length - occupiedHallIds.size - reservedHallIds.size - unavailableHallIds.size),
      },
      halls,
      lectures,
      reservations,
      todaysLectures: todaysLectures.sort((a, b) => a.start_at.localeCompare(b.start_at)),
      recent,
      lecturesByDay: [...byDay.entries()].map(([day, value]) => ({ name: getDayLabel(day), value, day })),
      hallTypes: Object.entries(halls.reduce((acc, hall) => ({ ...acc, [hall.type]: (acc[hall.type] || 0) + 1 }), {})).map(([name, value]) => ({ name, value })),
      subjectTypes: Object.entries(subjects.reduce((acc, subject) => ({ ...acc, [subject.type]: (acc[subject.type] || 0) + 1 }), {})).map(([name, value]) => ({ name, value })),
    }
  },
}

export function getActivityLabel(activity) {
  if (activity.activityType === 'lecture') return `تم تحديث محاضرة ${activity.subject?.title || ''}`
  return `تمت إضافة القاعة ${activity.title || ''}`
}
