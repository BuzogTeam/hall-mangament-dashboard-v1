-- REQUIRED RLS FOR THE NEW AUTHORIZATION TABLES
-- Run after schema.sql and functions.sql.
-- This file does not enable or change RLS on the existing academic tables.

-- Profiles: a normal user can read only their own row. A Super Admin can read
-- all rows for the Users page. There is intentionally no direct UPDATE policy:
-- update_my_profile() and admin_update_profile() are the only write paths.
drop policy if exists profiles_select_self_or_super_admin on public.profiles;
create policy profiles_select_self_or_super_admin
on public.profiles
for select to authenticated
using (id = auth.uid() or public.is_super_admin());

-- No INSERT/UPDATE/DELETE policies are created for profiles. The Auth trigger,
-- the two SECURITY DEFINER RPCs, and the server-only Edge Function own writes.

-- Authorization metadata is readable by active authenticated accounts. It does
-- not grant mutation rights, and all mutation privileges were revoked in schema.sql.
drop policy if exists roles_select_active on public.roles;
create policy roles_select_active
on public.roles
for select to authenticated
using (public.is_active_user());

drop policy if exists permissions_select_active on public.permissions;
create policy permissions_select_active
on public.permissions
for select to authenticated
using (public.is_active_user());

drop policy if exists role_permissions_select_active on public.role_permissions;
create policy role_permissions_select_active
on public.role_permissions
for select to authenticated
using (public.is_active_user());

-- There are deliberately no direct write policies for roles, permissions, or
-- role_permissions. set_role_permission() enforces active Super Admin access.
