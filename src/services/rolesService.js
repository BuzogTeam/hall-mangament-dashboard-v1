import { supabase } from '../lib/supabase'

export const rolesService = {
  async list() {
    const [{ data: roles, error: rolesError }, { data: permissions, error: permissionsError }, { data: links, error: linksError }] = await Promise.all([
      supabase.from('roles').select('key,label_ar,description,created_at').order('key'),
      supabase.from('permissions').select('key,label_ar,resource,action').order('resource').order('action'),
      supabase.from('role_permissions').select('role_key,permission_key'),
    ])
    if (rolesError) throw rolesError
    if (permissionsError) throw permissionsError
    if (linksError) throw linksError
    return { roles: roles || [], permissions: permissions || [], links: links || [] }
  },
  async setPermission(roleKey, permissionKey, enabled) {
    const { error } = await supabase.rpc('set_role_permission', {
      p_role_key: roleKey,
      p_permission_key: permissionKey,
      p_enabled: enabled,
    })
    if (error) throw error
  },
}
