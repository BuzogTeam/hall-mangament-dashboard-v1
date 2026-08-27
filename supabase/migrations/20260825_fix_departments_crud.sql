-- Targeted, non-destructive fix for the Departments CRUD issue.
-- The anonymous/Flutter behavior is intentionally not changed:
-- this file does NOT enable or disable RLS and does not grant anything to anon.
-- It only gives authenticated users the table grant and policies needed by the
-- dashboard when RLS is enabled.

grant select, insert, update, delete on public.departments to authenticated;

-- Prefix names so this migration does not replace a policy owned by another app.
drop policy if exists uhms_departments_select on public.departments;
create policy uhms_departments_select
on public.departments
for select to authenticated
using (
  public.has_permission('departments.view')
  and (
    not public.is_department_manager()
    or id = public.current_department_id()
  )
);

drop policy if exists uhms_departments_insert on public.departments;
create policy uhms_departments_insert
on public.departments
for insert to authenticated
with check (public.has_permission('departments.create'));

drop policy if exists uhms_departments_update on public.departments;
create policy uhms_departments_update
on public.departments
for update to authenticated
using (
  public.has_permission('departments.update')
  and (
    not public.is_department_manager()
    or id = public.current_department_id()
  )
)
with check (
  public.has_permission('departments.update')
  and (
    not public.is_department_manager()
    or id = public.current_department_id()
  )
);

drop policy if exists uhms_departments_delete on public.departments;
create policy uhms_departments_delete
on public.departments
for delete to authenticated
using (public.has_permission('departments.delete'));
