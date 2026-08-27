-- Targeted, non-destructive fix for Levels CRUD.
-- The live database returned 42501: new row violates row-level security policy
-- for table levels, even though the authenticated Super Admin has levels.create.
-- This migration only adds authenticated policies; it does not enable/disable RLS,
-- grant anything to anon, or alter/delete data.

drop policy if exists uhms_levels_select on public.levels;
create policy uhms_levels_select
on public.levels
for select to authenticated
using (public.has_permission('levels.view'));

drop policy if exists uhms_levels_insert on public.levels;
create policy uhms_levels_insert
on public.levels
for insert to authenticated
with check (public.has_permission('levels.create'));

drop policy if exists uhms_levels_update on public.levels;
create policy uhms_levels_update
on public.levels
for update to authenticated
using (public.has_permission('levels.update'))
with check (public.has_permission('levels.update'));

drop policy if exists uhms_levels_delete on public.levels;
create policy uhms_levels_delete
on public.levels
for delete to authenticated
using (public.has_permission('levels.delete'));
