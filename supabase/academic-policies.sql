-- OPTIONAL RLS FOR THE EXISTING ACADEMIC TABLES
-- Run only after confirming that the Flutter client authenticates with Supabase Auth
-- and can satisfy these policies. This file never deletes or changes rows, but enabling
-- RLS will block anonymous access unless an explicit policy allows it.
-- The policies below rely on helpers from functions.sql and permissions seeded by schema.sql.

-- Buildings are shared campus resources. Only users with the relevant permission can
-- read/write them; Department Managers receive no write permissions by default.
alter table public.buildings enable row level security;
drop policy if exists buildings_view on public.buildings;
create policy buildings_view on public.buildings
for select to authenticated
using (public.has_permission('buildings.view'));
drop policy if exists buildings_create on public.buildings;
create policy buildings_create on public.buildings
for insert to authenticated
with check (public.has_permission('buildings.create'));
drop policy if exists buildings_update on public.buildings;
create policy buildings_update on public.buildings
for update to authenticated
using (public.has_permission('buildings.update'))
with check (public.has_permission('buildings.update'));
drop policy if exists buildings_delete on public.buildings;
create policy buildings_delete on public.buildings
for delete to authenticated
using (public.has_permission('buildings.delete'));

-- Halls are shared resources because the existing schema has no department_id on halls.
alter table public.halls enable row level security;
drop policy if exists halls_view on public.halls;
create policy halls_view on public.halls
for select to authenticated
using (public.has_permission('halls.view'));
drop policy if exists halls_create on public.halls;
create policy halls_create on public.halls
for insert to authenticated
with check (public.has_permission('halls.create'));
drop policy if exists halls_update on public.halls;
create policy halls_update on public.halls
for update to authenticated
using (public.has_permission('halls.update'))
with check (public.has_permission('halls.update'));
drop policy if exists halls_delete on public.halls;
create policy halls_delete on public.halls
for delete to authenticated
using (public.has_permission('halls.delete'));

-- Departments: a Department Manager can see its own department only. Other roles
-- with department permissions can manage all departments.
alter table public.departments enable row level security;
drop policy if exists departments_view on public.departments;
create policy departments_view on public.departments
for select to authenticated
using (public.has_permission('departments.view')
  and (not public.is_department_manager() or id = public.current_department_id()));
drop policy if exists departments_create on public.departments;
create policy departments_create on public.departments
for insert to authenticated
with check (public.has_permission('departments.create'));
drop policy if exists departments_update on public.departments;
create policy departments_update on public.departments
for update to authenticated
using (public.has_permission('departments.update')
  and (not public.is_department_manager() or id = public.current_department_id()))
with check (public.has_permission('departments.update')
  and (not public.is_department_manager() or id = public.current_department_id()));
drop policy if exists departments_delete on public.departments;
create policy departments_delete on public.departments
for delete to authenticated
using (public.has_permission('departments.delete'));

-- Levels are shared reference data. The current schema has no department relation.
alter table public.levels enable row level security;
drop policy if exists levels_view on public.levels;
create policy levels_view on public.levels
for select to authenticated
using (public.has_permission('levels.view'));
drop policy if exists levels_create on public.levels;
create policy levels_create on public.levels
for insert to authenticated
with check (public.has_permission('levels.create'));
drop policy if exists levels_update on public.levels;
create policy levels_update on public.levels
for update to authenticated
using (public.has_permission('levels.update'))
with check (public.has_permission('levels.update'));
drop policy if exists levels_delete on public.levels;
create policy levels_delete on public.levels
for delete to authenticated
using (public.has_permission('levels.delete'));

-- Batches are the strongest department boundary available in the current model.
alter table public.batches enable row level security;
drop policy if exists batches_view on public.batches;
create policy batches_view on public.batches
for select to authenticated
using (public.has_permission('batches.view')
  and (not public.is_department_manager() or department_id = public.current_department_id()));
drop policy if exists batches_create on public.batches;
create policy batches_create on public.batches
for insert to authenticated
with check (public.has_permission('batches.create')
  and (not public.is_department_manager() or department_id = public.current_department_id()));
drop policy if exists batches_update on public.batches;
create policy batches_update on public.batches
for update to authenticated
using (public.has_permission('batches.update')
  and (not public.is_department_manager() or department_id = public.current_department_id()))
with check (public.has_permission('batches.update')
  and (not public.is_department_manager() or department_id = public.current_department_id()));
drop policy if exists batches_delete on public.batches;
create policy batches_delete on public.batches
for delete to authenticated
using (public.has_permission('batches.delete')
  and (not public.is_department_manager() or department_id = public.current_department_id()));

-- Subjects and instructors have no department_id or join table in the existing
-- schema. They are therefore global reference data; Department Managers receive
-- read-only permissions by default rather than a false department filter.
alter table public.subjects enable row level security;
drop policy if exists subjects_view on public.subjects;
create policy subjects_view on public.subjects
for select to authenticated
using (public.has_permission('subjects.view'));
drop policy if exists subjects_create on public.subjects;
create policy subjects_create on public.subjects
for insert to authenticated
with check (public.has_permission('subjects.create'));
drop policy if exists subjects_update on public.subjects;
create policy subjects_update on public.subjects
for update to authenticated
using (public.has_permission('subjects.update'))
with check (public.has_permission('subjects.update'));
drop policy if exists subjects_delete on public.subjects;
create policy subjects_delete on public.subjects
for delete to authenticated
using (public.has_permission('subjects.delete'));

alter table public.instructors enable row level security;
drop policy if exists instructors_view on public.instructors;
create policy instructors_view on public.instructors
for select to authenticated
using (public.has_permission('instructors.view'));
drop policy if exists instructors_create on public.instructors;
create policy instructors_create on public.instructors
for insert to authenticated
with check (public.has_permission('instructors.create'));
drop policy if exists instructors_update on public.instructors;
create policy instructors_update on public.instructors
for update to authenticated
using (public.has_permission('instructors.update'))
with check (public.has_permission('instructors.update'));
drop policy if exists instructors_delete on public.instructors;
create policy instructors_delete on public.instructors
for delete to authenticated
using (public.has_permission('instructors.delete'));

-- Lectures inherit Department Manager scope through lectures.batch_id -> batches.department_id.
-- A manager can schedule only a batch from their department, while shared halls and
-- instructors are still globally checked by the conflict RPC.
alter table public.lectures enable row level security;
drop policy if exists lectures_view on public.lectures;
create policy lectures_view on public.lectures
for select to authenticated
using (public.has_permission('lectures.view')
  and (not public.is_department_manager()
    or exists (select 1 from public.batches b
               where b.id = lectures.batch_id
                 and b.department_id = public.current_department_id())));
drop policy if exists lectures_create on public.lectures;
create policy lectures_create on public.lectures
for insert to authenticated
with check (public.has_permission('lectures.create')
  and (not public.is_department_manager()
    or exists (select 1 from public.batches b
               where b.id = batch_id
                 and b.department_id = public.current_department_id())));
drop policy if exists lectures_update on public.lectures;
create policy lectures_update on public.lectures
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
drop policy if exists lectures_cancel on public.lectures;
create policy lectures_cancel on public.lectures
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
