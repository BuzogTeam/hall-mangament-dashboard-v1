-- Targeted, non-destructive fix for Subjects CRUD.
-- The live database allowed INSERT for the authenticated Super Admin but filtered
-- UPDATE/DELETE, returning an empty representation. This migration adds the
-- missing authenticated policies and grants without changing RLS state, anon
-- access, relations, or rows.

grant select, insert, update, delete on public.subjects to authenticated;

drop policy if exists uhms_subjects_select on public.subjects;
create policy uhms_subjects_select
on public.subjects
for select to authenticated
using (public.has_permission('subjects.view'));

drop policy if exists uhms_subjects_insert on public.subjects;
create policy uhms_subjects_insert
on public.subjects
for insert to authenticated
with check (public.has_permission('subjects.create'));

drop policy if exists uhms_subjects_update on public.subjects;
create policy uhms_subjects_update
on public.subjects
for update to authenticated
using (public.has_permission('subjects.update'))
with check (public.has_permission('subjects.update'));

drop policy if exists uhms_subjects_delete on public.subjects;
create policy uhms_subjects_delete
on public.subjects
for delete to authenticated
using (public.has_permission('subjects.delete'));
