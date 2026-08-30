import { supabase } from '../lib/supabase'

function isMissingOccurrenceHistory(error) {
  return error?.code === 'PGRST205' || /lecture_occurrence_history.*schema cache|does not exist/i.test(error?.message || '')
}

export const lectureHistoryService = {
  async list(lectureId) {
    const [seriesResult, occurrenceResult] = await Promise.all([
      supabase
        .from('lecture_status_history')
        .select('id,lecture_id,old_canceled,new_canceled,changed_by,changed_at,reason')
        .eq('lecture_id', lectureId),
      supabase
        .from('lecture_occurrence_history')
        .select('id,lecture_id,occurrence_date,old_canceled,new_canceled,changed_by,changed_at,reason')
        .eq('lecture_id', lectureId),
    ])
    if (seriesResult.error) throw seriesResult.error
    if (occurrenceResult.error && !isMissingOccurrenceHistory(occurrenceResult.error)) throw occurrenceResult.error

    const series = (seriesResult.data || []).map((item) => ({ ...item, history_kind: 'series', occurrence_date: null }))
    const occurrences = occurrenceResult.error ? [] : (occurrenceResult.data || []).map((item) => ({ ...item, history_kind: 'occurrence' }))
    return [...series, ...occurrences].sort((a, b) => new Date(b.changed_at) - new Date(a.changed_at))
  },
}
