import { supabase } from '../lib/supabase'

export const conflictsService = {
  async list() {
    const { data, error } = await supabase.rpc('find_all_lecture_conflicts')
    if (error) throw error
    return data || []
  },
}
