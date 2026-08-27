-- Run this in Supabase SQL Editor with an owner/admin connection.
-- The publishable key can query data through PostgREST, but cannot inspect pg_catalog safely.

-- 1) Enum types and their exact values.
select
  n.nspname as schema_name,
  t.typname as enum_name,
  e.enumsortorder,
  e.enumlabel as allowed_value
from pg_type t
join pg_enum e on t.oid = e.enumtypid
join pg_namespace n on n.oid = t.typnamespace
where n.nspname = 'public'
order by t.typname, e.enumsortorder;

-- 2) Foreign keys and their referenced columns.
select
  tc.constraint_name,
  tc.table_schema,
  tc.table_name,
  kcu.column_name,
  ccu.table_name as referenced_table,
  ccu.column_name as referenced_column
from information_schema.table_constraints tc
join information_schema.key_column_usage kcu
  on tc.constraint_name = kcu.constraint_name
 and tc.table_schema = kcu.table_schema
join information_schema.constraint_column_usage ccu
  on ccu.constraint_name = tc.constraint_name
 and ccu.table_schema = tc.table_schema
where tc.constraint_type = 'FOREIGN KEY'
  and tc.table_schema = 'public'
order by tc.table_name, tc.constraint_name;

-- 3) Views and materialized views exposed by the public schema.
select table_schema, table_name, table_type
from information_schema.tables
where table_schema = 'public'
  and table_type in ('VIEW', 'BASE TABLE')
order by table_name;

-- 4) Public functions/RPCs.
select n.nspname as schema_name, p.proname as function_name,
       pg_get_function_identity_arguments(p.oid) as arguments,
       pg_get_function_result(p.oid) as return_type
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
order by p.proname;

-- 5) RLS status and policies.
select schemaname, tablename, rowsecurity, forcerowsecurity
from pg_tables
where schemaname = 'public'
order by tablename;

select schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
from pg_policies
where schemaname = 'public'
order by tablename, policyname;
