-- Targeted, non-destructive fix for Instructors CRUD.
-- The authenticated Super Admin has instructor permissions, but UPDATE/DELETE
-- currently return an empty result because the matching policies are missing.
-- This migration does not enable/disable RLS, grant anything to anon, or modify rows.

grant select, insert, update, delete on public.instructors to authenticated;

drop policy if exists uhms_instructors_select on public.instructors;
create policy uhms_instructors_select
on public.instructors
for select to authenticated
using (public.has_permission('instructors.view'));

drop policy if exists uhms_instructors_insert on public.instructors;
create policy uhms_instructors_insert
on public.instructors
for insert to authenticated
with check (public.has_permission('instructors.create'));

drop policy if exists uhms_instructors_update on public.instructors;
create policy uhms_instructors_update
on public.instructors
for update to authenticated
using (public.has_permission('instructors.update'))
with check (public.has_permission('instructors.update'));

drop policy if exists uhms_instructors_delete on public.instructors;
create policy uhms_instructors_delete
on public.instructors
for delete to authenticated
using (public.has_permission('instructors.delete'));
