-- Targeted, non-destructive fix for Batches CRUD.
-- The authenticated Super Admin can read/create batches, but an UPDATE currently
-- returns an empty representation because the matching RLS policy is missing.
-- This migration does not enable/disable RLS, grant anything to anon, or modify rows.

grant select, insert, update, delete on public.batches to authenticated;

drop policy if exists uhms_batches_select on public.batches;
create policy uhms_batches_select
on public.batches
for select to authenticated
using (
  public.has_permission('batches.view')
  and (
    not public.is_department_manager()
    or department_id = public.current_department_id()
  )
);

drop policy if exists uhms_batches_insert on public.batches;
create policy uhms_batches_insert
on public.batches
for insert to authenticated
with check (
  public.has_permission('batches.create')
  and (
    not public.is_department_manager()
    or department_id = public.current_department_id()
  )
);

drop policy if exists uhms_batches_update on public.batches;
create policy uhms_batches_update
on public.batches
for update to authenticated
using (
  public.has_permission('batches.update')
  and (
    not public.is_department_manager()
    or department_id = public.current_department_id()
  )
)
with check (
  public.has_permission('batches.update')
  and (
    not public.is_department_manager()
    or department_id = public.current_department_id()
  )
);

drop policy if exists uhms_batches_delete on public.batches;
create policy uhms_batches_delete
on public.batches
for delete to authenticated
using (
  public.has_permission('batches.delete')
  and (
    not public.is_department_manager()
    or department_id = public.current_department_id()
  )
);
