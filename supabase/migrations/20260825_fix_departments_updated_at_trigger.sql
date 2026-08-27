-- Non-destructive fix for:
-- record "new" has no field "updated_at"
--
-- A trigger on public.departments is calling a timestamp trigger function even
-- though departments has no updated_at column. This removes only the invalid
-- trigger(s) attached to departments whose function definition references
-- NEW.updated_at. It does not touch triggers on profiles or any other table,
-- and it does not delete or modify rows.

do $$
declare
  trigger_row record;
begin
  for trigger_row in
    select
      t.tgname as trigger_name,
      n.nspname as function_schema,
      p.proname as function_name
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace cn on cn.oid = c.relnamespace
    join pg_proc p on p.oid = t.tgfoid
    join pg_namespace n on n.oid = p.pronamespace
    where c.oid = 'public.departments'::regclass
      and cn.nspname = 'public'
      and not t.tgisinternal
      and pg_get_functiondef(p.oid) ~* 'new[[:space:]]*\.[[:space:]]*updated_at'
  loop
    execute format(
      'drop trigger if exists %I on public.departments',
      trigger_row.trigger_name
    );
  end loop;
end;
$$;
