import { ENUM_OPTIONS, uniqueValues } from '../lib/utils'
import { selectRows } from './baseService'

export const metadataService = {
  async getOptions() {
    const [halls, subjects, instructors, lectures] = await Promise.all([
      selectRows('halls', 'floor,type'),
      selectRows('subjects', 'type'),
      selectRows('instructors', 'type'),
      selectRows('lectures', 'day_of_week,group'),
    ])
    return {
      floors: uniqueValues(halls, 'floor').length ? uniqueValues(halls, 'floor') : ENUM_OPTIONS.floors,
      hallTypes: uniqueValues(halls, 'type').length ? uniqueValues(halls, 'type') : ENUM_OPTIONS.hallTypes,
      subjectTypes: uniqueValues(subjects, 'type').length ? uniqueValues(subjects, 'type') : ENUM_OPTIONS.subjectTypes,
      instructorTypes: uniqueValues(instructors, 'type').length ? uniqueValues(instructors, 'type') : ENUM_OPTIONS.instructorTypes,
      days: uniqueValues(lectures, 'day_of_week'),
      groups: uniqueValues(lectures, 'group').length ? uniqueValues(lectures, 'group') : ENUM_OPTIONS.groups,
    }
  },
}
