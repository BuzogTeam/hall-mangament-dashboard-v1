-- Non-destructive fix for invalid timestamp triggers on the existing academic tables.
--
-- The tables below do not have an updated_at column. Any trigger on them whose
-- function references NEW.updated_at is invalid and causes PostgreSQL error 42703
-- during UPDATE. This migration removes only those invalid triggers from those
-- specific tables. It does not touch profiles, lectures, other tables, functions,
-- columns, or data.

do $$
declare
  trigger_row record;
begin
  for trigger_row in
    select
      cn.nspname as table_schema,
      c.relname as table_name,
      t.tgname as trigger_name
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace cn on cn.oid = c.relnamespace
    join pg_proc p on p.oid = t.tgfoid
    where cn.nspname = 'public'
      and c.relname in (
        'buildings', 'halls', 'departments', 'levels',
        'batches', 'subjects', 'instructors'
      )
      and not t.tgisinternal
      and not exists (
        select 1
        from pg_attribute column_info
        where column_info.attrelid = c.oid
          and column_info.attname = 'updated_at'
          and column_info.attnum > 0
          and not column_info.attisdropped
      )
      and pg_get_functiondef(p.oid) ~* 'new[[:space:]]*\.[[:space:]]*updated_at'
  loop
    execute format(
      'drop trigger if exists %I on %I.%I',
      trigger_row.trigger_name,
      trigger_row.table_schema,
      trigger_row.table_name
    );
  end loop;
end;
$$;
