import { supabase } from '../lib/supabase'

export const lectureHistoryService = {
  async list(lectureId) {
    const { data, error } = await supabase
      .from('lecture_status_history')
      .select('id,lecture_id,old_canceled,new_canceled,changed_by,changed_at,reason')
      .eq('lecture_id', lectureId)
      .order('changed_at', { ascending: false })
    if (error) throw error
    return data || []
  },
}
