// Deploy with: supabase functions deploy create-user
// Set SUPABASE_SERVICE_ROLE_KEY only in the Edge Function secrets, never in VITE_*.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  try {
    const authorization = request.headers.get('Authorization')
    if (!authorization) throw new Error('غير مصرح')
    const url = Deno.env.get('SUPABASE_URL')
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY')
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
    if (!url || !anonKey || !serviceKey) throw new Error('إعدادات Edge Function ناقصة')

    const callerClient = createClient(url, anonKey, { global: { headers: { Authorization: authorization } } })
    const { data: { user: caller }, error: callerError } = await callerClient.auth.getUser()
    if (callerError || !caller) throw new Error('جلسة غير صالحة')

    const adminClient = createClient(url, serviceKey)
    const { data: callerProfile, error: profileError } = await adminClient.from('profiles').select('role,is_active').eq('id', caller.id).single()
    if (profileError || callerProfile?.role !== 'super_admin' || !callerProfile.is_active) throw new Error('يتطلب إنشاء المستخدم صلاحية مدير النظام الأعلى')

    const body = await request.json()
    const email = String(body.email || '').trim().toLowerCase()
    const fullName = String(body.full_name || '').trim()
    const role = String(body.role || 'viewer')
    const departmentId = body.department_id || null
    const scopes = Array.isArray(body.scopes) ? body.scopes : (role === 'department_manager' && departmentId ? [{ department_id: Number(departmentId), level_id: null }] : [])
    const allowedRoles = ['admin', 'schedule_manager', 'department_manager', 'viewer']
    if (!email || !fullName || !allowedRoles.includes(role)) throw new Error('بيانات المستخدم غير صحيحة')
    if (role === 'department_manager' && !scopes.length) throw new Error('يجب تحديد قسم أو نطاق لمدير القسم')

    const { data: invitation, error: inviteError } = await adminClient.auth.admin.inviteUserByEmail(email, {
      data: { full_name: fullName },
    })
    if (inviteError) throw inviteError
    const { error: upsertError } = await adminClient.from('profiles').upsert({
      id: invitation.user.id,
      email,
      full_name: fullName,
      role,
      department_id: departmentId ? Number(departmentId) : null,
      is_active: true,
      updated_at: new Date().toISOString(),
    })
    if (upsertError) throw upsertError

    if (role === 'department_manager') {
      const cleanedScopes = scopes.map((scope) => ({
        profile_id: invitation.user.id,
        department_id: Number(scope.department_id),
        level_id: scope.level_id === null || scope.level_id === undefined || scope.level_id === '' ? null : Number(scope.level_id),
      }))
      if (cleanedScopes.some((scope) => !Number.isInteger(scope.department_id) || scope.department_id <= 0 || (scope.level_id !== null && (!Number.isInteger(scope.level_id) || scope.level_id <= 0)))) throw new Error('نطاق مدير القسم غير صحيح')
      const { error: clearScopeError } = await adminClient.from('department_manager_scopes').delete().eq('profile_id', invitation.user.id)
      if (clearScopeError) throw clearScopeError
      const { error: scopeError } = await adminClient.from('department_manager_scopes').insert(cleanedScopes)
      if (scopeError) throw scopeError
    }

    return new Response(JSON.stringify({ id: invitation.user.id, email }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
  } catch (error) {
    return new Response(JSON.stringify({ error: error.message || 'تعذر إنشاء المستخدم' }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
  }
})
