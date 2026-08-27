-- Read-only diagnostics for CRUD/RLS issues.
-- This file does not insert, update, delete, or change schema.

-- 1) RLS status on the academic table that is being tested.
select schemaname, tablename, rowsecurity, forcerowsecurity
from pg_tables
where schemaname = 'public'
  and tablename in ('departments', 'buildings', 'halls', 'levels', 'batches', 'subjects', 'instructors', 'lectures')
order by tablename;

-- 2) Policies currently installed for departments, levels, and batches.
select schemaname, tablename, policyname, roles, cmd, qual, with_check
from pg_policies
where schemaname = 'public'
  and tablename in ('departments', 'levels', 'batches')
order by tablename, policyname;

-- 3) Grants for the browser roles.
select grantee, table_name, privilege_type
from information_schema.role_table_grants
where table_schema = 'public'
  and table_name = 'departments'
  and grantee in ('anon', 'authenticated')
order by grantee, privilege_type;

-- 4) Confirm the row still exists and inspect its current values.
select id, title, abbreviation, num_levels, created_at
from public.departments
where id = 18;

-- 5) Show non-internal triggers on academic tables. A trigger function that
-- references NEW.updated_at is invalid on tables that do not have that column.
select
  c.relname as table_name,
  t.tgname as trigger_name,
  n.nspname as function_schema,
  p.proname as function_name,
  pg_get_triggerdef(t.oid) as trigger_definition,
  pg_get_functiondef(p.oid) as function_definition
from pg_trigger t
join pg_class c on c.oid = t.tgrelid
join pg_proc p on p.oid = t.tgfoid
join pg_namespace n on n.oid = p.pronamespace
where c.relnamespace = 'public'::regnamespace
  and c.relname in ('buildings', 'halls', 'departments', 'levels', 'batches', 'subjects', 'instructors', 'lectures')
  and not t.tgisinternal
order by c.relname, t.tgname;

-- 6) Confirm the RPCs used by the dashboard exist and who can execute them.
select routine_schema, routine_name, routine_type, data_type
from information_schema.routines
where routine_schema = 'public'
  and routine_name in (
    'update_my_profile', 'admin_update_profile', 'set_role_permission',
    'find_lecture_conflicts', 'set_lecture_canceled', 'set_lecture_canceled_with_reason',
    'save_lecture_atomic', 'find_all_lecture_conflicts'
  )
order by routine_name;
