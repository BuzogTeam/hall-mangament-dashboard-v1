import { ENUM_OPTIONS, normalizeGroups, uniqueValues } from '../lib/utils'
import { selectRows } from './baseService'

export const metadataService = {
  async getOptions() {
    const [halls, subjects, instructors, lectures] = await Promise.all([
      selectRows('halls', 'floor,type'),
      selectRows('subjects', 'type'),
      selectRows('instructors', 'type'),
      selectRows('lectures', 'day_of_week,groups'),
    ])
    const groupValues = normalizeGroups((lectures || []).flatMap((lecture) => lecture.groups || []))
    return {
      floors: uniqueValues(halls, 'floor').length ? uniqueValues(halls, 'floor') : ENUM_OPTIONS.floors,
      hallTypes: uniqueValues(halls, 'type').length ? uniqueValues(halls, 'type') : ENUM_OPTIONS.hallTypes,
      subjectTypes: uniqueValues(subjects, 'type').length ? uniqueValues(subjects, 'type') : ENUM_OPTIONS.subjectTypes,
      instructorTypes: uniqueValues(instructors, 'type').length ? uniqueValues(instructors, 'type') : ENUM_OPTIONS.instructorTypes,
      days: uniqueValues(lectures, 'day_of_week'),
      groups: groupValues.length ? groupValues : ENUM_OPTIONS.groups,
    }
  },
}
