import { supabase } from '../lib/supabase'

export async function signIn({ email, password }) {
  const { data, error } = await supabase.auth.signInWithPassword({ email, password })
  if (error) throw error
  return data
}

export async function signOut() {
  const { error } = await supabase.auth.signOut()
  if (error) throw error
}

export async function getSession() {
  const { data, error } = await supabase.auth.getSession()
  if (error) throw error
  return data.session
}

export async function getProfile(userId) {
  if (!userId) return { profile: null, setupRequired: false }
  const { data, error } = await supabase.from('profiles').select('*').eq('id', userId).maybeSingle()
  if (error) {
    const missing = error.code === 'PGRST205' || /profiles.*schema cache|does not exist/i.test(error.message || '')
    if (missing) return { profile: null, setupRequired: true }
    throw error
  }
  if (!data) return { profile: null, setupRequired: false }
  const { data: permissionRows, error: permissionsError } = await supabase
    .from('role_permissions')
    .select('permission_key')
    .eq('role_key', data.role)
  if (permissionsError) throw permissionsError
  const { data: scopeRows, error: scopesError } = await supabase
    .from('department_manager_scopes')
    .select('department_id,level_id')
    .eq('profile_id', userId)
  const scopesMissing = scopesError?.code === 'PGRST205' || /department_manager_scopes.*schema cache|does not exist/i.test(scopesError?.message || '')
  if (scopesError && !scopesMissing) throw scopesError
  return { profile: { ...data, permissions: (permissionRows || []).map((row) => row.permission_key), permissionsLoaded: true, departmentScopes: scopesMissing ? [] : (scopeRows || []) }, setupRequired: false }
}

export function onAuthStateChange(callback) {
  return supabase.auth.onAuthStateChange(callback)
}

export async function updateProfile(_userId, payload) {
  // There is no direct profiles UPDATE grant for the browser.
  if (payload.full_name === undefined || Object.keys(payload).some((key) => key !== 'full_name')) {
    throw new Error('يمكن تعديل الاسم الشخصي فقط من خلال هذا المسار الآمن')
  }
  const { data, error } = await supabase.rpc('update_my_profile', { new_full_name: payload.full_name })
  if (error) throw error
  return data
}

export async function updatePassword(password) {
  const { data, error } = await supabase.auth.updateUser({ password })
  if (error) throw error
  return data
}
