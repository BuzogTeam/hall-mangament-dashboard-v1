import { supabase } from '../lib/supabase'

export const usersService = {
  async list() {
    const { data, error } = await supabase.from('profiles').select('id,full_name,email,role,department_id,is_active,created_at,updated_at,department:departments(id,title,abbreviation)').order('created_at', { ascending: false })
    if (error) throw error
    let scopes = []
    const scopeResult = await supabase.from('department_manager_scopes').select('profile_id,department_id,level_id')
    const missing = scopeResult.error?.code === 'PGRST205' || /department_manager_scopes.*schema cache|does not exist/i.test(scopeResult.error?.message || '')
    if (scopeResult.error && !missing) throw scopeResult.error
    if (!missing) scopes = scopeResult.data || []
    return (data || []).map((profile) => ({ ...profile, departmentScopes: scopes.filter((scope) => scope.profile_id === profile.id) }))
  },
  async update(id, payload) {
    const { scopes = [], ...profilePatch } = payload || {}
    const { data, error } = await supabase.rpc('admin_update_profile_with_scopes', { p_user_id: id, p_patch: profilePatch, p_scopes: scopes })
    if (!error) return data
    const missing = error.code === 'PGRST202' || /function .*admin_update_profile_with_scopes.*not found|could not find the function/i.test(error.message || '')
    if (!missing) throw error
    // Compatibility path for a staged rollout; run the scope migration to make
    // scope writes atomic and authoritative.
    const fallback = await supabase.rpc('admin_update_profile', { p_user_id: id, p_patch: profilePatch })
    if (fallback.error) throw fallback.error
    if (scopes.length || profilePatch.role === 'department_manager') {
      const scopeResult = await supabase.rpc('admin_set_department_manager_scopes', { p_user_id: id, p_scopes: scopes })
      if (scopeResult.error) throw scopeResult.error
    }
    return fallback.data
  },
  async create(payload) {
    const { data, error } = await supabase.functions.invoke('create-user', { body: payload })
    if (error) throw error
    if (data?.error) throw new Error(data.error)
    return data
  },
}
