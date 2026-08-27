-- Canonical non-destructive CRUD policy migration for the existing academic tables.
--
-- Use this file for an installation where INSERT works but UPDATE/DELETE return
-- an empty representation, or where authenticated INSERT is rejected by RLS.
-- It intentionally does NOT ALTER TABLE ... ENABLE/DISABLE ROW LEVEL SECURITY,
-- does not grant anything to anon, and does not modify or delete rows. This keeps
-- the current Flutter read behavior unchanged while completing policies for the
-- already-RLS-protected authenticated path.
--
-- Run after schema.sql/functions.sql/policies.sql.

-- Buildings: shared resource.
drop policy if exists uhms_academic_buildings_select on public.buildings;
create policy uhms_academic_buildings_select on public.buildings
for select to authenticated using (public.has_permission('buildings.view'));
drop policy if exists uhms_academic_buildings_insert on public.buildings;
create policy uhms_academic_buildings_insert on public.buildings
for insert to authenticated with check (public.has_permission('buildings.create'));
drop policy if exists uhms_academic_buildings_update on public.buildings;
create policy uhms_academic_buildings_update on public.buildings
for update to authenticated
using (public.has_permission('buildings.update'))
with check (public.has_permission('buildings.update'));
drop policy if exists uhms_academic_buildings_delete on public.buildings;
create policy uhms_academic_buildings_delete on public.buildings
for delete to authenticated using (public.has_permission('buildings.delete'));

-- Halls: shared resource because the current schema has no department_id.
drop policy if exists uhms_academic_halls_select on public.halls;
create policy uhms_academic_halls_select on public.halls
for select to authenticated using (public.has_permission('halls.view'));
drop policy if exists uhms_academic_halls_insert on public.halls;
create policy uhms_academic_halls_insert on public.halls
for insert to authenticated with check (public.has_permission('halls.create'));
drop policy if exists uhms_academic_halls_update on public.halls;
create policy uhms_academic_halls_update on public.halls
for update to authenticated
using (public.has_permission('halls.update'))
with check (public.has_permission('halls.update'));
drop policy if exists uhms_academic_halls_delete on public.halls;
create policy uhms_academic_halls_delete on public.halls
for delete to authenticated using (public.has_permission('halls.delete'));

-- Departments: Department Managers are limited to their own department.
drop policy if exists uhms_academic_departments_select on public.departments;
create policy uhms_academic_departments_select on public.departments
for select to authenticated
using (public.has_permission('departments.view')
  and (not public.is_department_manager() or id = public.current_department_id()));
drop policy if exists uhms_academic_departments_insert on public.departments;
create policy uhms_academic_departments_insert on public.departments
for insert to authenticated with check (public.has_permission('departments.create'));
drop policy if exists uhms_academic_departments_update on public.departments;
create policy uhms_academic_departments_update on public.departments
for update to authenticated
using (public.has_permission('departments.update')
  and (not public.is_department_manager() or id = public.current_department_id()))
with check (public.has_permission('departments.update')
  and (not public.is_department_manager() or id = public.current_department_id()));
drop policy if exists uhms_academic_departments_delete on public.departments;
create policy uhms_academic_departments_delete on public.departments
for delete to authenticated using (public.has_permission('departments.delete'));

-- Levels: shared reference data.
drop policy if exists uhms_academic_levels_select on public.levels;
create policy uhms_academic_levels_select on public.levels
for select to authenticated using (public.has_permission('levels.view'));
drop policy if exists uhms_academic_levels_insert on public.levels;
create policy uhms_academic_levels_insert on public.levels
for insert to authenticated with check (public.has_permission('levels.create'));
drop policy if exists uhms_academic_levels_update on public.levels;
create policy uhms_academic_levels_update on public.levels
for update to authenticated
using (public.has_permission('levels.update'))
with check (public.has_permission('levels.update'));
drop policy if exists uhms_academic_levels_delete on public.levels;
create policy uhms_academic_levels_delete on public.levels
for delete to authenticated using (public.has_permission('levels.delete'));

-- Batches: the main department boundary.
drop policy if exists uhms_academic_batches_select on public.batches;
create policy uhms_academic_batches_select on public.batches
for select to authenticated
using (public.has_permission('batches.view')
  and (not public.is_department_manager() or department_id = public.current_department_id()));
drop policy if exists uhms_academic_batches_insert on public.batches;
create policy uhms_academic_batches_insert on public.batches
for insert to authenticated
with check (public.has_permission('batches.create')
  and (not public.is_department_manager() or department_id = public.current_department_id()));
drop policy if exists uhms_academic_batches_update on public.batches;
create policy uhms_academic_batches_update on public.batches
for update to authenticated
using (public.has_permission('batches.update')
  and (not public.is_department_manager() or department_id = public.current_department_id()))
with check (public.has_permission('batches.update')
  and (not public.is_department_manager() or department_id = public.current_department_id()));
drop policy if exists uhms_academic_batches_delete on public.batches;
create policy uhms_academic_batches_delete on public.batches
for delete to authenticated
using (public.has_permission('batches.delete')
  and (not public.is_department_manager() or department_id = public.current_department_id()));

-- Subjects: global reference data in the current schema.
drop policy if exists uhms_academic_subjects_select on public.subjects;
create policy uhms_academic_subjects_select on public.subjects
for select to authenticated using (public.has_permission('subjects.view'));
drop policy if exists uhms_academic_subjects_insert on public.subjects;
create policy uhms_academic_subjects_insert on public.subjects
for insert to authenticated with check (public.has_permission('subjects.create'));
drop policy if exists uhms_academic_subjects_update on public.subjects;
create policy uhms_academic_subjects_update on public.subjects
for update to authenticated
using (public.has_permission('subjects.update'))
with check (public.has_permission('subjects.update'));
drop policy if exists uhms_academic_subjects_delete on public.subjects;
create policy uhms_academic_subjects_delete on public.subjects
for delete to authenticated using (public.has_permission('subjects.delete'));

-- Instructors: global reference data in the current schema.
drop policy if exists uhms_academic_instructors_select on public.instructors;
create policy uhms_academic_instructors_select on public.instructors
for select to authenticated using (public.has_permission('instructors.view'));
drop policy if exists uhms_academic_instructors_insert on public.instructors;
create policy uhms_academic_instructors_insert on public.instructors
for insert to authenticated with check (public.has_permission('instructors.create'));
drop policy if exists uhms_academic_instructors_update on public.instructors;
create policy uhms_academic_instructors_update on public.instructors
for update to authenticated
using (public.has_permission('instructors.update'))
with check (public.has_permission('instructors.update'));
drop policy if exists uhms_academic_instructors_delete on public.instructors;
create policy uhms_academic_instructors_delete on public.instructors
for delete to authenticated using (public.has_permission('instructors.delete'));

-- Lectures inherit the Department Manager boundary through batch_id.
drop policy if exists uhms_academic_lectures_select on public.lectures;
create policy uhms_academic_lectures_select on public.lectures
for select to authenticated
using (public.has_permission('lectures.view')
  and (not public.is_department_manager()
    or exists (select 1 from public.batches b
               where b.id = lectures.batch_id
                 and b.department_id = public.current_department_id())));
drop policy if exists uhms_academic_lectures_insert on public.lectures;
create policy uhms_academic_lectures_insert on public.lectures
for insert to authenticated
with check (public.has_permission('lectures.create')
  and (not public.is_department_manager()
    or exists (select 1 from public.batches b
               where b.id = batch_id
                 and b.department_id = public.current_department_id())));
drop policy if exists uhms_academic_lectures_update on public.lectures;
create policy uhms_academic_lectures_update on public.lectures
for update to authenticated
using (public.has_permission('lectures.update')
  and (not public.is_department_manager()
    or exists (select 1 from public.batches b
               where b.id = lectures.batch_id
                 and b.department_id = public.current_department_id())))
with check (public.has_permission('lectures.update')
  and (not public.is_department_manager()
    or exists (select 1 from public.batches b
               where b.id = batch_id
                 and b.department_id = public.current_department_id())));
drop policy if exists uhms_academic_lectures_cancel on public.lectures;
create policy uhms_academic_lectures_cancel on public.lectures
for update to authenticated
using (public.has_permission('lectures.cancel')
  and (not public.is_department_manager()
    or exists (select 1 from public.batches b
               where b.id = lectures.batch_id
                 and b.department_id = public.current_department_id())))
with check (public.has_permission('lectures.cancel')
  and (not public.is_department_manager()
    or exists (select 1 from public.batches b
               where b.id = batch_id
                 and b.department_id = public.current_department_id())));
