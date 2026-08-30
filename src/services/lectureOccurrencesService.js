import { supabase } from '../lib/supabase'

export const lectureOccurrencesService = {
  async listForRange(startDate, endDate) {
    const { data, error } = await supabase
      .from('lecture_occurrence_overrides')
      .select('id,lecture_id,occurrence_date,status,reason,changed_by,changed_at')
      .gte('occurrence_date', startDate)
      .lte('occurrence_date', endDate)
    if (error) {
      const missing = error.code === 'PGRST205' || /lecture_occurrence_overrides.*schema cache|does not exist/i.test(error.message || '')
      if (missing) return []
      throw error
    }
    return data || []
  },
  async setCanceled(lectureId, occurrenceDate, canceled, reason = '') {
    const { data, error } = await supabase.rpc('set_lecture_occurrence_canceled', {
      p_lecture_id: Number(lectureId),
      p_occurrence_date: occurrenceDate,
      p_canceled: Boolean(canceled),
      p_reason: reason?.trim() || null,
    })
    if (error) throw error
    return data
  },
}
