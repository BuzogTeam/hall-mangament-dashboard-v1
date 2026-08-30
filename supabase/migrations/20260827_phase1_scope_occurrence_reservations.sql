-- Phase 1 additive migration: scoped Department Managers, temporary lecture
-- occurrences, and weekly/date-aware hall reservations.
--
-- Existing department_levels, department_manager_scopes, hall_reservations,
-- schedule_hardening functions, and academic tables are reused. This file does
-- not recreate them and does not delete/truncate academic data.
-- Date-specific reservations are handled by exact occurrence_date checks; they
-- are never converted to a weekday and therefore never block every week.
-- Run after the migrations already applied in this project.

/* -------------------------------------------------------------------------- */
/* 0. Fail-closed prerequisite check                                          */
/* -------------------------------------------------------------------------- */

-- This migration is intentionally incremental. Refuse to run before the
-- already-applied scope/reservation migration instead of creating duplicate
-- tables or silently targeting a different legacy shape. The check runs before
-- any permission/catalog change.
do $$
declare
  required_table text;
  required_column text;
begin
  foreach required_table in array array[
    'departments', 'levels', 'batches', 'halls', 'lectures', 'profiles',
    'permissions', 'role_permissions', 'department_levels',
    'department_manager_scopes', 'hall_reservations'
  ] loop
    if to_regclass(format('public.%I', required_table)) is null then
      raise exception 'required table public.% does not exist; run only after the existing base/scope migrations', required_table
        using errcode = '42P01';
    end if;
  end loop;

  foreach required_column in array array['department_id', 'level_id', 'is_active'] loop
    if not exists (
      select 1 from pg_attribute
      where attrelid = 'public.department_levels'::regclass
        and attname = required_column
        and attnum > 0
        and not attisdropped
    ) then
      raise exception 'public.department_levels.% is missing; this migration cannot infer a compatible schema', required_column
        using errcode = '42703';
    end if;
  end loop;

  foreach required_column in array array['profile_id', 'department_id', 'level_id'] loop
    if not exists (
      select 1 from pg_attribute
      where attrelid = 'public.department_manager_scopes'::regclass
        and attname = required_column
        and attnum > 0
        and not attisdropped
    ) then
      raise exception 'public.department_manager_scopes.% is missing; this migration cannot infer a compatible schema', required_column
        using errcode = '42703';
    end if;
  end loop;

  foreach required_column in array array[
    'id', 'hall_id', 'day_of_week', 'start_at', 'end_at', 'status',
    'reason', 'notes', 'created_by', 'updated_by', 'created_at', 'updated_at'
  ] loop
    if not exists (
      select 1 from pg_attribute
      where attrelid = 'public.hall_reservations'::regclass
        and attname = required_column
        and attnum > 0
        and not attisdropped
    ) then
      raise exception 'public.hall_reservations.% is missing; this migration cannot infer a compatible schema', required_column
        using errcode = '42703';
    end if;
  end loop;

  foreach required_column in array array[
    'id', 'day_of_week', 'start_at', 'end_at', 'subject_id', 'hall_id',
    'instructor_id', 'canceled', 'group', 'batch_id'
  ] loop
    if not exists (
      select 1 from pg_attribute
      where attrelid = 'public.lectures'::regclass
        and attname = required_column
        and attnum > 0
        and not attisdropped
    ) then
      raise exception 'public.lectures.% is missing; this migration cannot infer a compatible schema', required_column
        using errcode = '42703';
    end if;
  end loop;

  if not exists (
    select 1 from pg_attribute
    where attrelid = 'public.halls'::regclass
      and attname = 'booking'
      and atttypid = 'boolean'::regtype
      and attnum > 0
      and not attisdropped
  ) then
    raise exception 'public.halls.booking boolean column is required for the global scheduling block'
      using errcode = '42703';
  end if;

  if to_regprocedure('public.admin_update_profile(uuid,jsonb)') is null
     or to_regprocedure('public.admin_set_department_levels(bigint,jsonb)') is null
     or to_regprocedure('public.uhms_enum_value_exists(regclass,name,text)') is null then
    raise exception 'required base/scope RPC is missing; do not run this phase migration out of order'
      using errcode = '42883';
  end if;
end;
$$;

/* -------------------------------------------------------------------------- */
/* 1. Permissions                                                             */
/* -------------------------------------------------------------------------- */

insert into public.permissions(key, label_ar, resource, action) values
  ('lectures.cancel_series', 'إلغاء السلسلة الأسبوعية', 'lectures', 'cancel_series'),
  ('lectures.cancel_occurrence', 'إلغاء محاضرة لتاريخ محدد', 'lectures', 'cancel_occurrence'),
  ('hall_reservations.view', 'عرض حجوزات القاعات', 'hall_reservations', 'view'),
  ('hall_reservations.create', 'إنشاء حجوزات القاعات', 'hall_reservations', 'create'),
  ('hall_reservations.update', 'تعديل حجوزات القاعات', 'hall_reservations', 'update'),
  ('hall_reservations.cancel', 'إلغاء حجوزات القاعات', 'hall_reservations', 'cancel')
on conflict (key) do nothing;

insert into public.role_permissions(role_key, permission_key)
select 'super_admin', key from public.permissions
on conflict do nothing;

insert into public.role_permissions(role_key, permission_key)
select 'admin', key from public.permissions
where key not like 'users.%' and key not like 'roles.%'
on conflict do nothing;

insert into public.role_permissions(role_key, permission_key) values
  ('schedule_manager', 'lectures.cancel_series'),
  ('schedule_manager', 'lectures.cancel_occurrence'),
  ('schedule_manager', 'hall_reservations.view'),
  ('schedule_manager', 'hall_reservations.create'),
  ('schedule_manager', 'hall_reservations.update'),
  ('schedule_manager', 'hall_reservations.cancel'),
  ('department_manager', 'lectures.cancel_occurrence'),
  ('department_manager', 'hall_reservations.view'),
  ('viewer', 'hall_reservations.view')
on conflict do nothing;

-- This is the only intentional change to existing authorization data: remove
-- obsolete global-series grants from Department Managers. Academic rows are not
-- touched, and the statement is idempotent.
delete from public.role_permissions
where role_key = 'department_manager'
  and permission_key in ('lectures.cancel', 'lectures.cancel_series');

/* -------------------------------------------------------------------------- */
/* 2. Reuse existing hall_reservations and extend it safely                   */
/* -------------------------------------------------------------------------- */

alter table public.hall_reservations
  add column if not exists reservation_date date;

alter table public.hall_reservations
  alter column day_of_week drop not null;

do $$
begin
  if not exists (
    select 1
    from pg_attribute
    where attrelid = 'public.hall_reservations'::regclass
      and attname = 'reservation_date'
      and atttypid = 'date'::regtype
      and attnum > 0
      and not attisdropped
  ) then
    raise exception 'public.hall_reservations.reservation_date must be a date column'
      using errcode = '42804';
  end if;
end;
$$;

-- Do not drop an unknown Flutter/application constraint. Add only a
-- namespaced invariant for the two supported reservation targets. Existing
-- weekly rows already have day_of_week and therefore remain valid.
do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.hall_reservations'::regclass
      and conname = 'uhms_phase1_hall_reservations_target_check'
  ) then
    execute 'alter table public.hall_reservations
      add constraint uhms_phase1_hall_reservations_target_check
      check ((reservation_date is not null) <> (day_of_week is not null))';
  end if;
end;
$$;

create index if not exists hall_reservations_hall_date_idx
on public.hall_reservations(hall_id, reservation_date, start_at, end_at)
where status = 'active' and reservation_date is not null;

-- Keep the established RPC-only write boundary for the reused tables. These
-- grants/revokes are idempotent and do not remove any existing read access.
grant select on public.department_levels, public.department_manager_scopes, public.hall_reservations to authenticated;
revoke insert, update, delete, truncate on public.department_levels, public.department_manager_scopes, public.hall_reservations from anon, authenticated;
alter table public.department_levels enable row level security;
alter table public.department_manager_scopes enable row level security;
alter table public.hall_reservations enable row level security;

/* -------------------------------------------------------------------------- */
/* 2A. Scope enforcement and department/level integrity                       */
/* -------------------------------------------------------------------------- */

-- An explicit scope is authoritative. A Department Manager with no scope, or
-- with a scope for a different profile department, receives no department/level
-- data through these helpers. This deliberately removes the old implicit
-- profiles.department_id fallback.
create or replace function public.department_manager_scope_allowed(
  p_department_id bigint,
  p_level_id bigint default null
)
returns boolean
security definer
set search_path = public, pg_temp
language plpgsql
stable
as $$
begin
  if auth.uid() is null or not public.is_active_user() then
    return false;
  end if;
  if public.current_role_key() <> 'department_manager' then
    return true;
  end if;
  if p_department_id is null then
    return false;
  end if;

  return exists (
    select 1
    from public.department_manager_scopes s
    where s.profile_id = auth.uid()
      and s.department_id = p_department_id
      and s.department_id = public.current_department_id()
      and (
        p_level_id is null
        or (
          (s.level_id is null or s.level_id = p_level_id)
          and exists (
            select 1
            from public.department_levels dl
            where dl.department_id = p_department_id
              and dl.level_id = p_level_id
              and dl.is_active = true
          )
        )
      )
  );
end;
$$;

create or replace function public.department_manager_level_allowed(p_level_id bigint)
returns boolean
security definer
set search_path = public, pg_temp
language plpgsql
stable
as $$
begin
  if auth.uid() is null or not public.is_active_user() then
    return false;
  end if;
  if public.current_role_key() <> 'department_manager' then
    return true;
  end if;
  if p_level_id is null then
    return false;
  end if;

  return exists (
    select 1
    from public.department_manager_scopes s
    join public.department_levels dl
      on dl.department_id = s.department_id
     and dl.level_id = p_level_id
     and dl.is_active = true
    where s.profile_id = auth.uid()
      and s.department_id = public.current_department_id()
      and (s.level_id is null or s.level_id = p_level_id)
  );
end;
$$;

revoke all on function public.department_manager_scope_allowed(bigint, bigint) from public, anon;
revoke all on function public.department_manager_level_allowed(bigint) from public, anon;
grant execute on function public.department_manager_scope_allowed(bigint, bigint) to authenticated;
grant execute on function public.department_manager_level_allowed(bigint) to authenticated;

-- Validate the official department/level relationship on every scope write, not
-- only through the browser RPC. Direct client writes are already revoked, but
-- this trigger also protects future privileged integrations.
create or replace function public.uhms_validate_department_manager_scope()
returns trigger
security definer
set search_path = public, pg_temp
language plpgsql
as $$
declare
  target_role text;
  target_department_id bigint;
begin
  select p.role, p.department_id
    into target_role, target_department_id
  from public.profiles p
  where p.id = new.profile_id;

  if target_role is distinct from 'department_manager' then
    raise exception 'scopes can only be assigned to a department_manager' using errcode = '42501';
  end if;
  if target_department_id is null or new.department_id <> target_department_id then
    raise exception 'scope department must match the profile department' using errcode = '42501';
  end if;
  if new.level_id is not null and not exists (
    select 1
    from public.department_levels dl
    where dl.department_id = new.department_id
      and dl.level_id = new.level_id
      and dl.is_active = true
  ) then
    raise exception 'scope level is not assigned to the selected department' using errcode = '42501';
  end if;
  return new;
end;
$$;

revoke all on function public.uhms_validate_department_manager_scope() from public, anon, authenticated;

do $$
begin
  if not exists (
    select 1
    from pg_trigger
    where tgname = 'uhms_phase1_validate_department_manager_scope'
      and tgrelid = 'public.department_manager_scopes'::regclass
      and not tgisinternal
  ) then
    execute 'create trigger uhms_phase1_validate_department_manager_scope
      before insert or update on public.department_manager_scopes
      for each row execute function public.uhms_validate_department_manager_scope()';
  end if;
end;
$$;

-- Keep the existing RPC name/signature used by the dashboard, but make its
-- validation strict and atomic for the one-department scope model.
create or replace function public.admin_set_department_manager_scopes(
  p_user_id uuid,
  p_scopes jsonb
)
returns void
security definer
set search_path = public, pg_temp
language plpgsql
as $$
declare
  target_profile public.profiles;
  scope_item jsonb;
  scope_department_id bigint;
  scope_level_id bigint;
  target_department_id bigint;
  scope_has_level boolean;
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if not public.is_active_user() or not public.is_super_admin() then
    raise exception 'only an active super_admin may manage department scopes' using errcode = '42501';
  end if;
  if p_user_id is null then
    raise exception 'p_user_id is required' using errcode = '22023';
  end if;
  if p_scopes is null or jsonb_typeof(p_scopes) <> 'array' then
    raise exception 'p_scopes must be a JSON array' using errcode = '22023';
  end if;

  select *
    into target_profile
  from public.profiles
  where id = p_user_id
  for update;
  if target_profile.id is null then
    raise exception 'profile was not found' using errcode = 'P0002';
  end if;
  if target_profile.role <> 'department_manager' then
    if jsonb_array_length(p_scopes) > 0 then
      raise exception 'scopes can only be assigned to a department_manager' using errcode = '22023';
    end if;
    delete from public.department_manager_scopes where profile_id = p_user_id;
    return;
  end if;

  target_department_id := target_profile.department_id;
  if jsonb_array_length(p_scopes) > 0 and target_department_id is null then
    raise exception 'a department_manager must have a profile department before scopes are assigned' using errcode = '22023';
  end if;

  for scope_item in select value from jsonb_array_elements(p_scopes)
  loop
    if jsonb_typeof(scope_item) <> 'object'
       or not (scope_item ? 'department_id')
       or jsonb_typeof(scope_item -> 'department_id') <> 'number'
       or coalesce((scope_item ->> 'department_id') !~ '^[1-9][0-9]*$', true) then
      raise exception 'each scope needs a positive integer department_id' using errcode = '22023';
    end if;

    scope_department_id := (scope_item ->> 'department_id')::bigint;
    if scope_department_id <> target_department_id then
      raise exception 'scope department must match the profile department' using errcode = '42501';
    end if;
    if not exists (select 1 from public.departments where id = scope_department_id) then
      raise exception 'scope department does not exist' using errcode = '23503';
    end if;

    scope_has_level := scope_item ? 'level_id' and jsonb_typeof(scope_item -> 'level_id') <> 'null';
    if not scope_has_level then
      scope_level_id := null;
    elsif jsonb_typeof(scope_item -> 'level_id') = 'number'
      and not coalesce((scope_item ->> 'level_id') !~ '^[1-9][0-9]*$', true) then
      scope_level_id := (scope_item ->> 'level_id')::bigint;
    else
      raise exception 'scope level_id must be a positive integer or null' using errcode = '22023';
    end if;

    if scope_level_id is not null and not exists (
      select 1
      from public.department_levels dl
      where dl.department_id = scope_department_id
        and dl.level_id = scope_level_id
        and dl.is_active = true
    ) then
      raise exception 'scope level is not assigned to the selected department' using errcode = '42501';
    end if;
  end loop;

  delete from public.department_manager_scopes where profile_id = p_user_id;
  insert into public.department_manager_scopes(profile_id, department_id, level_id)
  select p_user_id,
         (item ->> 'department_id')::bigint,
         case
           when jsonb_typeof(item -> 'level_id') = 'number'
             then (item ->> 'level_id')::bigint
           else null
         end
  from jsonb_array_elements(p_scopes) as items(item);
end;
$$;

grant execute on function public.admin_set_department_manager_scopes(uuid, jsonb) to authenticated;
revoke execute on function public.admin_set_department_manager_scopes(uuid, jsonb) from public, anon;

create or replace function public.admin_update_profile_with_scopes(
  p_user_id uuid,
  p_patch jsonb,
  p_scopes jsonb
)
returns public.profiles
security definer
set search_path = public, pg_temp
language plpgsql
as $$
declare
  updated_profile public.profiles;
begin
  updated_profile := public.admin_update_profile(p_user_id, p_patch);
  perform public.admin_set_department_manager_scopes(p_user_id, coalesce(p_scopes, '[]'::jsonb));
  return updated_profile;
end;
$$;

grant execute on function public.admin_update_profile_with_scopes(uuid, jsonb, jsonb) to authenticated;
revoke execute on function public.admin_update_profile_with_scopes(uuid, jsonb, jsonb) from public, anon;

/* -------------------------------------------------------------------------- */
/* 3. Temporary occurrence cancellation                                       */
/* -------------------------------------------------------------------------- */

create table if not exists public.lecture_occurrence_overrides (
  id bigint generated always as identity primary key,
  lecture_id bigint not null references public.lectures(id) on delete restrict,
  occurrence_date date not null,
  status text not null default 'canceled' check (status = 'canceled'),
  reason text,
  changed_by uuid references auth.users(id) on delete set null,
  changed_at timestamptz not null default now(),
  constraint lecture_occurrence_override_reason_check check (reason is null or char_length(reason) <= 500),
  constraint lecture_occurrence_override_unique unique (lecture_id, occurrence_date)
);

create index if not exists lecture_occurrence_overrides_date_idx
on public.lecture_occurrence_overrides(occurrence_date, lecture_id);

create index if not exists lecture_occurrence_overrides_lecture_idx
on public.lecture_occurrence_overrides(lecture_id, occurrence_date);

grant select on public.lecture_occurrence_overrides to authenticated;
revoke insert, update, delete, truncate on public.lecture_occurrence_overrides from anon, authenticated;
alter table public.lecture_occurrence_overrides enable row level security;

drop policy if exists uhms_lecture_occurrence_overrides_select on public.lecture_occurrence_overrides;
create policy uhms_lecture_occurrence_overrides_select
on public.lecture_occurrence_overrides
for select to authenticated
using (
  public.has_permission('lectures.view')
  and exists (
    select 1 from public.lectures l
    join public.batches b on b.id = l.batch_id
    where l.id = lecture_occurrence_overrides.lecture_id
      and (
        not public.is_department_manager()
        or public.department_manager_scope_allowed(b.department_id, b.level_id)
      )
  )
);

create table if not exists public.lecture_occurrence_history (
  id bigint generated always as identity primary key,
  lecture_id bigint not null references public.lectures(id) on delete restrict,
  occurrence_date date not null,
  old_canceled boolean not null,
  new_canceled boolean not null,
  reason text,
  changed_by uuid references auth.users(id) on delete set null,
  changed_at timestamptz not null default now(),
  constraint lecture_occurrence_history_state_check check (old_canceled is distinct from new_canceled),
  constraint lecture_occurrence_history_reason_check check (reason is null or char_length(reason) <= 500)
);

create index if not exists lecture_occurrence_history_lookup_idx
on public.lecture_occurrence_history(lecture_id, occurrence_date, changed_at desc);

grant select on public.lecture_occurrence_history to authenticated;
revoke insert, update, delete, truncate on public.lecture_occurrence_history from anon, authenticated;
alter table public.lecture_occurrence_history enable row level security;

drop policy if exists uhms_lecture_occurrence_history_select on public.lecture_occurrence_history;
create policy uhms_lecture_occurrence_history_select
on public.lecture_occurrence_history
for select to authenticated
using (
  public.has_permission('lectures.view')
  and exists (
    select 1 from public.lectures l
    join public.batches b on b.id = l.batch_id
    where l.id = lecture_occurrence_history.lecture_id
      and (not public.is_department_manager() or public.department_manager_scope_allowed(b.department_id, b.level_id))
  )
);

create or replace function public.uhms_record_lecture_occurrence_history()
returns trigger
security definer
set search_path = public, pg_temp
language plpgsql
as $$
declare status_reason text;
begin
  status_reason := nullif(left(current_setting('app.occurrence_status_reason', true), 500), '');
  if tg_op = 'INSERT' then
    insert into public.lecture_occurrence_history(lecture_id, occurrence_date, old_canceled, new_canceled, reason, changed_by)
    values (new.lecture_id, new.occurrence_date, false, true, status_reason, auth.uid());
  elsif tg_op = 'DELETE' then
    insert into public.lecture_occurrence_history(lecture_id, occurrence_date, old_canceled, new_canceled, reason, changed_by)
    values (old.lecture_id, old.occurrence_date, true, false, status_reason, auth.uid());
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

revoke all on function public.uhms_record_lecture_occurrence_history() from public, anon, authenticated;

do $$
begin
  if not exists (
    select 1 from pg_trigger
    where tgname = 'uhms_lecture_occurrence_history_trigger'
      and tgrelid = 'public.lecture_occurrence_overrides'::regclass
      and not tgisinternal
  ) then
    execute 'create trigger uhms_lecture_occurrence_history_trigger after insert or delete on public.lecture_occurrence_overrides for each row execute function public.uhms_record_lecture_occurrence_history()';
  end if;
end;
$$;

create or replace function public.set_lecture_occurrence_canceled(
  p_lecture_id bigint,
  p_occurrence_date date,
  p_canceled boolean,
  p_reason text default null
)
returns public.lecture_occurrence_overrides
security definer
set search_path = public, pg_temp
language plpgsql
as $$
declare
  target_lecture public.lectures;
  target_batch public.batches;
  saved_override public.lecture_occurrence_overrides;
  clean_reason text := nullif(btrim(coalesce(p_reason, '')), '');
begin
  if auth.uid() is null or not public.is_active_user() then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if not public.has_permission('lectures.cancel_occurrence') then
    raise exception 'the current user cannot cancel a lecture occurrence' using errcode = '42501';
  end if;
  if p_lecture_id is null or p_lecture_id <= 0 or p_occurrence_date is null or p_canceled is null then
    raise exception 'lecture, occurrence date and canceled state are required' using errcode = '22023';
  end if;
  if clean_reason is not null and char_length(clean_reason) > 500 then
    raise exception 'reason must not exceed 500 characters' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(918273645::bigint);
  select * into target_lecture from public.lectures where id = p_lecture_id for update;
  if target_lecture.id is null then
    raise exception 'lecture was not found' using errcode = 'P0002';
  end if;
  select * into target_batch from public.batches where id = target_lecture.batch_id;
  if public.is_department_manager()
     and not public.department_manager_scope_allowed(target_batch.department_id, target_batch.level_id) then
    raise exception 'the lecture is outside the current scope' using errcode = '42501';
  end if;
  if extract(dow from p_occurrence_date)::integer <> (
    case target_lecture.day_of_week::text
      when 'احد' then 0 when 'أثنين' then 1 when 'ثلاثاء' then 2
      when 'اربعاء' then 3 when 'خميس' then 4 when 'جمعة' then 5 when 'سبت' then 6
      else -1
    end
  ) then
    raise exception 'occurrence_date does not match the lecture day_of_week' using errcode = '22023';
  end if;

  perform set_config('app.occurrence_status_reason', coalesce(clean_reason, ''), true);
  if p_canceled then
    insert into public.lecture_occurrence_overrides(lecture_id, occurrence_date, status, reason, changed_by)
    values (p_lecture_id, p_occurrence_date, 'canceled', clean_reason, auth.uid())
    on conflict (lecture_id, occurrence_date) do update
      set reason = excluded.reason, changed_by = excluded.changed_by, changed_at = now()
    returning * into saved_override;
    perform set_config('app.occurrence_status_reason', '', true);
    return saved_override;
  end if;

  -- Reopening an occurrence must respect global hall blocks, weekly reservations,
  -- one-time reservations, and other active lecture occurrences.
  if target_lecture.canceled then
    raise exception 'the master lecture is globally canceled' using errcode = '42501';
  end if;
  if exists (select 1 from public.halls where id = target_lecture.hall_id and booking = true) then
    raise exception 'لا يمكن تفعيل occurrence لأن القاعة غير متاحة للجدولة' using errcode = 'P0001';
  end if;
  if exists (
    select 1 from public.hall_reservations r
    where r.hall_id = target_lecture.hall_id and r.status = 'active'
      and r.day_of_week = target_lecture.day_of_week::text
      and target_lecture.start_at < r.end_at and target_lecture.end_at > r.start_at
  ) then
    raise exception 'لا يمكن تفعيل occurrence لأن القاعة محجوزة أسبوعيًا' using errcode = 'P0001';
  end if;
  if exists (
    select 1 from public.hall_reservations r
    where r.hall_id = target_lecture.hall_id and r.status = 'active'
      and r.reservation_date = p_occurrence_date
      and target_lecture.start_at < r.end_at and target_lecture.end_at > r.start_at
  ) then
    raise exception 'لا يمكن تفعيل occurrence لأن القاعة محجوزة في هذا التاريخ' using errcode = 'P0001';
  end if;
  if exists (
    select 1 from public.lectures l
    where l.id <> target_lecture.id and l.canceled = false
      and l.day_of_week = target_lecture.day_of_week
      and l.hall_id = target_lecture.hall_id
      and target_lecture.start_at < l.end_at and target_lecture.end_at > l.start_at
      and not exists (select 1 from public.lecture_occurrence_overrides o where o.lecture_id = l.id and o.occurrence_date = p_occurrence_date)
  ) then
    raise exception 'لا يمكن تفعيل occurrence بسبب تعارض القاعة' using errcode = 'P0001';
  end if;
  if exists (
    select 1 from public.lectures l
    where l.id <> target_lecture.id and l.canceled = false
      and l.day_of_week = target_lecture.day_of_week
      and l.instructor_id = target_lecture.instructor_id
      and target_lecture.start_at < l.end_at and target_lecture.end_at > l.start_at
      and not exists (select 1 from public.lecture_occurrence_overrides o where o.lecture_id = l.id and o.occurrence_date = p_occurrence_date)
  ) then
    raise exception 'لا يمكن تفعيل occurrence بسبب تعارض المدرس' using errcode = 'P0001';
  end if;
  if exists (
    select 1 from public.lectures l
    where l.id <> target_lecture.id and l.canceled = false
      and l.day_of_week = target_lecture.day_of_week
      and l.batch_id = target_lecture.batch_id
      and target_lecture.start_at < l.end_at and target_lecture.end_at > l.start_at
      and not exists (select 1 from public.lecture_occurrence_overrides o where o.lecture_id = l.id and o.occurrence_date = p_occurrence_date)
  ) then
    raise exception 'لا يمكن تفعيل occurrence بسبب تعارض الدفعة' using errcode = 'P0001';
  end if;

  delete from public.lecture_occurrence_overrides
  where lecture_id = p_lecture_id and occurrence_date = p_occurrence_date;
  perform set_config('app.occurrence_status_reason', '', true);
  return null;
end;
$$;

grant execute on function public.set_lecture_occurrence_canceled(bigint, date, boolean, text) to authenticated;
revoke execute on function public.set_lecture_occurrence_canceled(bigint, date, boolean, text) from public, anon;

/* -------------------------------------------------------------------------- */
/* 4. Helpful date functions                                                   */
/* -------------------------------------------------------------------------- */

create or replace function public.uhms_date_matches_lecture_day(p_date date, p_day_of_week text)
returns boolean
security definer
set search_path = public, pg_temp
language sql
immutable
as $$
  select case extract(dow from p_date)::integer
    when 0 then p_day_of_week = 'احد'
    when 1 then p_day_of_week = 'أثنين'
    when 2 then p_day_of_week = 'ثلاثاء'
    when 3 then p_day_of_week = 'اربعاء'
    when 4 then p_day_of_week = 'خميس'
    when 5 then p_day_of_week = 'جمعة'
    when 6 then p_day_of_week = 'سبت'
    else false
  end;
$$;

revoke all on function public.uhms_date_matches_lecture_day(date, text) from public, anon, authenticated;

/* -------------------------------------------------------------------------- */
/* 5. Scope RLS: restrictive, namespaced, no old-policy deletion               */
/* -------------------------------------------------------------------------- */

drop policy if exists uhms_phase1_scope_departments on public.departments;
create policy uhms_phase1_scope_departments on public.departments as restrictive
for all to authenticated
using (not public.is_department_manager() or public.department_manager_scope_allowed(id, null))
with check (not public.is_department_manager() or public.department_manager_scope_allowed(id, null));

drop policy if exists uhms_phase1_scope_levels on public.levels;
create policy uhms_phase1_scope_levels on public.levels as restrictive
for all to authenticated
using (not public.is_department_manager() or public.department_manager_level_allowed(id))
with check (not public.is_department_manager() or public.department_manager_level_allowed(id));

drop policy if exists uhms_phase1_scope_batches on public.batches;
create policy uhms_phase1_scope_batches on public.batches as restrictive
for all to authenticated
using (
  not public.is_department_manager()
  or public.department_manager_scope_allowed(department_id, level_id)
)
with check (
  not public.is_department_manager()
  or public.department_manager_scope_allowed(department_id, level_id)
);

drop policy if exists uhms_phase1_scope_lectures on public.lectures;
create policy uhms_phase1_scope_lectures on public.lectures as restrictive
for all to authenticated
using (
  not public.is_department_manager()
  or exists (select 1 from public.batches b where b.id = lectures.batch_id and public.department_manager_scope_allowed(b.department_id, b.level_id))
)
with check (
  not public.is_department_manager()
  or exists (select 1 from public.batches b where b.id = batch_id and public.department_manager_scope_allowed(b.department_id, b.level_id))
);

create index if not exists batches_department_level_idx on public.batches(department_id, level_id);
create index if not exists lectures_batch_day_time_idx on public.lectures(batch_id, day_of_week, start_at, end_at) where canceled = false;

-- These restrictive policies narrow any existing permissive policy; they do not
-- replace or delete Flutter/application policies. RPCs run as SECURITY DEFINER
-- and remain the only client write path for scopes and mappings.
drop policy if exists uhms_phase1_scope_department_manager_scopes on public.department_manager_scopes;
create policy uhms_phase1_scope_department_manager_scopes
on public.department_manager_scopes as restrictive
for all to authenticated
using (not public.is_department_manager() or profile_id = auth.uid())
with check (not public.is_department_manager() or profile_id = auth.uid());

drop policy if exists uhms_phase1_scope_department_levels on public.department_levels;
create policy uhms_phase1_scope_department_levels
on public.department_levels as restrictive
for all to authenticated
using (
  public.is_active_user()
  and (
    not public.is_department_manager()
    or public.department_manager_scope_allowed(department_id, level_id)
  )
)
with check (
  public.is_active_user()
  and (
    not public.is_department_manager()
    or public.department_manager_scope_allowed(department_id, level_id)
  )
);

/* SCHEDULE_RPC_OVERRIDES_PHASE1 */
create or replace function public.uhms_validate_lecture_conflicts()
returns trigger
security definer
set search_path = public, pg_temp
language plpgsql
as $$
begin
  if tg_op = 'UPDATE'
     and old.canceled is distinct from new.canceled
     and not public.has_permission('lectures.cancel_series') then
    raise exception 'لا تملك صلاحية تغيير الحالة العامة للمحاضرة' using errcode = '42501';
  end if;

  -- Canceled lectures do not reserve resources.
  if new.canceled then
    return new;
  end if;

  -- Use the same transaction-level lock as save_lecture_atomic() and the
  -- reservation RPC before reading either resource table. This ordering is
  -- what closes the lecture-versus-reservation race for direct table writes.
  perform pg_advisory_xact_lock(918273645::bigint);

  if exists (select 1 from public.halls where id = new.hall_id and booking = true) then
    raise exception 'لا يمكن حفظ المحاضرة: القاعة غير متاحة للجدولة' using errcode = 'P0001';
  end if;
  if exists (
    select 1 from public.hall_reservations r
    where r.hall_id = new.hall_id
      and r.status = 'active'
      and (
        (r.reservation_date is null and r.day_of_week = new.day_of_week::text)
        or (
          r.reservation_date is not null
          and public.uhms_date_matches_lecture_day(r.reservation_date, new.day_of_week::text)
          and not exists (
            select 1 from public.lecture_occurrence_overrides o
            where o.lecture_id = new.id and o.occurrence_date = r.reservation_date
          )
        )
      )
      and new.start_at < r.end_at
      and new.end_at > r.start_at
  ) then
    raise exception 'لا يمكن حفظ المحاضرة: القاعة محجوزة في هذا الوقت' using errcode = 'P0001';
  end if;

  -- An edit of only subject/group does not create a new schedule conflict. This
  -- also lets administrators repair existing legacy conflicts without changing
  -- their time/resource allocation first.
  if tg_op = 'UPDATE'
     and old.day_of_week is not distinct from new.day_of_week
     and old.start_at is not distinct from new.start_at
     and old.end_at is not distinct from new.end_at
     and old.hall_id is not distinct from new.hall_id
     and old.instructor_id is not distinct from new.instructor_id
     and old.batch_id is not distinct from new.batch_id
     and old.canceled is not distinct from new.canceled then
    return new;
  end if;

  if exists (
    select 1 from public.lectures l
    where l.id <> new.id
      and l.canceled = false
      and l.day_of_week = new.day_of_week
      and l.hall_id = new.hall_id
      and new.start_at < l.end_at
      and new.end_at > l.start_at
  ) then
    raise exception 'لا يمكن حفظ المحاضرة: يوجد تعارض في القاعة' using errcode = 'P0001';
  end if;

  if exists (
    select 1 from public.lectures l
    where l.id <> new.id
      and l.canceled = false
      and l.day_of_week = new.day_of_week
      and l.instructor_id = new.instructor_id
      and new.start_at < l.end_at
      and new.end_at > l.start_at
  ) then
    raise exception 'لا يمكن حفظ المحاضرة: يوجد تعارض في المدرس' using errcode = 'P0001';
  end if;

  if exists (
    select 1 from public.lectures l
    where l.id <> new.id
      and l.canceled = false
      and l.day_of_week = new.day_of_week
      and l.batch_id = new.batch_id
      and new.start_at < l.end_at
      and new.end_at > l.start_at
  ) then
    raise exception 'لا يمكن حفظ المحاضرة: يوجد تعارض في الدفعة' using errcode = 'P0001';
  end if;

  return new;
end;
$$;

revoke all on function public.uhms_validate_lecture_conflicts() from public, anon, authenticated;

-- The hardening migration normally created this trigger. Create only this
-- namespaced trigger if it is missing; never drop or replace Flutter triggers.
do $$
begin
  if not exists (
    select 1
    from pg_trigger
    where tgname = 'uhms_lectures_conflict_guard'
      and tgrelid = 'public.lectures'::regclass
      and not tgisinternal
  ) then
    execute 'create trigger uhms_lectures_conflict_guard
      before insert or update on public.lectures
      for each row execute function public.uhms_validate_lecture_conflicts()';
  end if;
end;
$$;

-- Serialize administrative booking-flag changes with schedule writes. This
-- prevents a schedule transaction that started before booking=true from
-- committing after the hall has become unavailable. Existing schedules are
-- intentionally not auto-canceled.
create or replace function public.uhms_lock_hall_booking_change()
returns trigger
security definer
set search_path = public, pg_temp
language plpgsql
as $$
begin
  if old.booking is distinct from new.booking then
    perform pg_advisory_xact_lock(918273645::bigint);
  end if;
  return new;
end;
$$;

revoke all on function public.uhms_lock_hall_booking_change() from public, anon, authenticated;

do $$
begin
  if not exists (
    select 1
    from pg_trigger
    where tgname = 'uhms_phase1_hall_booking_lock'
      and tgrelid = 'public.halls'::regclass
      and not tgisinternal
  ) then
    execute 'create trigger uhms_phase1_hall_booking_lock
      before update of booking on public.halls
      for each row execute function public.uhms_lock_hall_booking_change()';
  end if;
end;
$$;

create or replace function public.save_lecture_atomic(
  p_lecture_id bigint,
  p_payload jsonb
)
returns public.lectures
security definer
set search_path = public, pg_temp
language plpgsql
as $$
declare
  current_lecture public.lectures;
  saved_lecture public.lectures;
  day_type text;
  group_type text;
  day_value text;
  group_value text;
  start_value time;
  end_value time;
  subject_value bigint;
  hall_value bigint;
  instructor_value bigint;
  batch_value bigint;
  schedule_changed boolean := true;
  conflict_message text := 'لا يمكن حفظ المحاضرة بسبب: ';
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if not public.is_active_user() then
    raise exception 'profile is inactive' using errcode = '42501';
  end if;
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'lecture payload must be a JSON object' using errcode = '22023';
  end if;
  if p_payload ? 'canceled' then
    raise exception 'canceled must be changed through the lifecycle RPC' using errcode = '42501';
  end if;

  if p_lecture_id is null then
    if not public.has_permission('lectures.create') then
      raise exception 'the current user cannot create lectures' using errcode = '42501';
    end if;
  else
    if p_lecture_id <= 0 or not public.has_permission('lectures.update') then
      raise exception 'the current user cannot update lectures' using errcode = '42501';
    end if;
  end if;

  -- Serialize schedule writes performed by this system. The conflict trigger
  -- uses the same lock, so direct table writes cannot race with this RPC.
  perform pg_advisory_xact_lock(918273645::bigint);

  if p_lecture_id is not null then
    select * into current_lecture
    from public.lectures
    where id = p_lecture_id
    for update;
    if current_lecture.id is null then
      raise exception 'lecture was not found' using errcode = 'P0002';
    end if;
  end if;

  day_value := btrim(p_payload ->> 'day_of_week');
  group_value := btrim(p_payload ->> 'group');
  if day_value is null or day_value = '' or group_value is null or group_value = '' then
    raise exception 'day_of_week and group are required' using errcode = '22023';
  end if;
  if (p_payload ->> 'start_at') !~ '^([01][0-9]|2[0-3]):[0-5][0-9](:[0-5][0-9])?$'
     or (p_payload ->> 'end_at') !~ '^([01][0-9]|2[0-3]):[0-5][0-9](:[0-5][0-9])?$' then
    raise exception 'start_at and end_at must be valid times' using errcode = '22023';
  end if;
  start_value := (p_payload ->> 'start_at')::time;
  end_value := (p_payload ->> 'end_at')::time;
  if start_value >= end_value then
    raise exception 'start_at must be earlier than end_at' using errcode = '22023';
  end if;
  if (p_payload ->> 'subject_id') !~ '^[1-9][0-9]*$'
     or (p_payload ->> 'hall_id') !~ '^[1-9][0-9]*$'
     or (p_payload ->> 'instructor_id') !~ '^[1-9][0-9]*$'
     or (p_payload ->> 'batch_id') !~ '^[1-9][0-9]*$' then
    raise exception 'subject_id, hall_id, instructor_id and batch_id must be positive integers' using errcode = '22023';
  end if;
  subject_value := (p_payload ->> 'subject_id')::bigint;
  hall_value := (p_payload ->> 'hall_id')::bigint;
  instructor_value := (p_payload ->> 'instructor_id')::bigint;
  batch_value := (p_payload ->> 'batch_id')::bigint;

  if not public.uhms_enum_value_exists('public.lectures'::regclass, 'day_of_week', day_value) then
    raise exception 'day_of_week is not a valid value' using errcode = '22023';
  end if;
  if not public.uhms_enum_value_exists('public.lectures'::regclass, 'group', group_value) then
    raise exception 'group is not a valid value' using errcode = '22023';
  end if;
  select format('%I.%I', n.nspname, t.typname)
    into day_type
  from pg_attribute a
  join pg_type t on t.oid = a.atttypid
  join pg_namespace n on n.oid = t.typnamespace
  where a.attrelid = 'public.lectures'::regclass
    and a.attname = 'day_of_week'
    and a.attnum > 0
    and not a.attisdropped;
  select format('%I.%I', n.nspname, t.typname)
    into group_type
  from pg_attribute a
  join pg_type t on t.oid = a.atttypid
  join pg_namespace n on n.oid = t.typnamespace
  where a.attrelid = 'public.lectures'::regclass
    and a.attname = 'group'
    and a.attnum > 0
    and not a.attisdropped;

  if not exists (select 1 from public.subjects where id = subject_value) then
    raise exception 'subject_id does not reference an existing subject' using errcode = '23503';
  end if;
  if not exists (select 1 from public.halls where id = hall_value) then
    raise exception 'hall_id does not reference an existing hall' using errcode = '23503';
  end if;
  if not exists (select 1 from public.instructors where id = instructor_value) then
    raise exception 'instructor_id does not reference an existing instructor' using errcode = '23503';
  end if;
  if not exists (select 1 from public.batches where id = batch_value) then
    raise exception 'batch_id does not reference an existing batch' using errcode = '23503';
  end if;
  if exists (select 1 from public.halls where id = hall_value and booking = true) then
    raise exception 'لا يمكن حفظ المحاضرة: القاعة غير متاحة للجدولة' using errcode = 'P0001';
  end if;
  if exists (
    select 1 from public.hall_reservations r
    where r.hall_id = hall_value
      and r.status = 'active'
      and (
        (r.reservation_date is null and r.day_of_week = day_value)
        or (
          r.reservation_date is not null
          and public.uhms_date_matches_lecture_day(r.reservation_date, day_value)
          and not exists (
            select 1 from public.lecture_occurrence_overrides o
            where o.lecture_id = p_lecture_id and o.occurrence_date = r.reservation_date
          )
        )
      )
      and start_value < r.end_at
      and end_value > r.start_at
  ) then
    raise exception 'لا يمكن حفظ المحاضرة: القاعة محجوزة في هذا الوقت' using errcode = 'P0001';
  end if;
  if public.is_department_manager() and not exists (
    select 1 from public.batches b
    where b.id = batch_value
      and public.department_manager_scope_allowed(b.department_id, b.level_id)
  ) then
    raise exception 'the batch is outside the current department' using errcode = '42501';
  end if;

  if p_lecture_id is not null then
    schedule_changed := current_lecture.day_of_week::text is distinct from day_value
      or current_lecture.start_at is distinct from start_value
      or current_lecture.end_at is distinct from end_value
      or current_lecture.hall_id is distinct from hall_value
      or current_lecture.instructor_id is distinct from instructor_value
      or current_lecture.batch_id is distinct from batch_value;
  end if;

  -- Do not let the current active schedule create a new resource conflict. A
  -- canceled lecture can be edited freely; reactivation checks separately.
  if p_lecture_id is null or (not current_lecture.canceled and schedule_changed) then
    if exists (
      select 1 from public.lectures l
      where (p_lecture_id is null or l.id <> p_lecture_id)
        and l.canceled = false
        and l.day_of_week::text = day_value
        and l.hall_id = hall_value
        and start_value < l.end_at and end_value > l.start_at
    ) then conflict_message := conflict_message || 'القاعة، '; end if;
    if exists (
      select 1 from public.lectures l
      where (p_lecture_id is null or l.id <> p_lecture_id)
        and l.canceled = false
        and l.day_of_week::text = day_value
        and l.instructor_id = instructor_value
        and start_value < l.end_at and end_value > l.start_at
    ) then conflict_message := conflict_message || 'المدرس، '; end if;
    if exists (
      select 1 from public.lectures l
      where (p_lecture_id is null or l.id <> p_lecture_id)
        and l.canceled = false
        and l.day_of_week::text = day_value
        and l.batch_id = batch_value
        and start_value < l.end_at and end_value > l.start_at
    ) then conflict_message := conflict_message || 'الدفعة، '; end if;
    if conflict_message <> 'لا يمكن حفظ المحاضرة بسبب: ' then
      raise exception '%', rtrim(conflict_message, '، ') using errcode = 'P0001';
    end if;
  end if;

  if p_lecture_id is null then
    execute format(
      'insert into public.lectures (day_of_week, start_at, end_at, subject_id, hall_id, instructor_id, canceled, "group", batch_id, updated_at)
       values ($1::%s, $2, $3, $4, $5, $6, false, $7::%s, $8, now()) returning *',
      day_type, group_type
    ) into saved_lecture
    using day_value, start_value, end_value, subject_value, hall_value, instructor_value, group_value, batch_value;
  else
    execute format(
      'update public.lectures
       set day_of_week = $1::%s, start_at = $2, end_at = $3, subject_id = $4, hall_id = $5, instructor_id = $6, "group" = $7::%s, batch_id = $8, updated_at = now()
       where id = $9 returning *',
      day_type, group_type
    ) into saved_lecture
    using day_value, start_value, end_value, subject_value, hall_value, instructor_value, group_value, batch_value, p_lecture_id;
  end if;

  if saved_lecture.id is null then
    raise exception 'lecture was not saved' using errcode = 'P0002';
  end if;
  return saved_lecture;
end;
$$;

grant execute on function public.save_lecture_atomic(bigint, jsonb) to authenticated;
revoke execute on function public.save_lecture_atomic(bigint, jsonb) from public, anon;

create or replace function public.set_lecture_canceled_with_reason(
  p_lecture_id bigint,
  p_canceled boolean,
  p_reason text default null
)
returns public.lectures
security definer
set search_path = public, pg_temp
language plpgsql
as $$
declare
  target_lecture public.lectures;
  clean_reason text := nullif(btrim(coalesce(p_reason, '')), '');
  hall_conflict boolean := false;
  instructor_conflict boolean := false;
  batch_conflict boolean := false;
  conflict_message text := 'لا يمكن إعادة تفعيل المحاضرة بسبب: ';
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if not public.is_active_user() or not public.has_permission('lectures.cancel_series') then
    raise exception 'the current user cannot change lecture cancellation state' using errcode = '42501';
  end if;
  if p_lecture_id is null or p_lecture_id <= 0 or p_canceled is null then
    raise exception 'lecture id and canceled state are required' using errcode = '22023';
  end if;
  if clean_reason is not null and char_length(clean_reason) > 500 then
    raise exception 'reason must not exceed 500 characters' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(918273645::bigint);
  select * into target_lecture
  from public.lectures
  where id = p_lecture_id
  for update;
  if target_lecture.id is null then
    raise exception 'lecture was not found' using errcode = 'P0002';
  end if;
  if public.is_department_manager() and not exists (
    select 1 from public.batches b
    where b.id = target_lecture.batch_id
      and public.department_manager_scope_allowed(b.department_id, b.level_id)
  ) then
    raise exception 'the lecture is outside the current department' using errcode = '42501';
  end if;
  if target_lecture.canceled = p_canceled then
    return target_lecture;
  end if;

  if p_canceled = false and exists (select 1 from public.halls where id = target_lecture.hall_id and booking = true) then
    raise exception 'لا يمكن إعادة تفعيل المحاضرة: القاعة غير متاحة للجدولة' using errcode = 'P0001';
  end if;
  if p_canceled = false and exists (
    select 1 from public.hall_reservations r
    where r.hall_id = target_lecture.hall_id
      and r.status = 'active'
      and (
        (r.reservation_date is null and r.day_of_week = target_lecture.day_of_week::text)
        or (
          r.reservation_date is not null
          and public.uhms_date_matches_lecture_day(r.reservation_date, target_lecture.day_of_week::text)
          and not exists (select 1 from public.lecture_occurrence_overrides o where o.lecture_id = target_lecture.id and o.occurrence_date = r.reservation_date)
        )
      )
      and target_lecture.start_at < r.end_at
      and target_lecture.end_at > r.start_at
  ) then
    raise exception 'لا يمكن إعادة تفعيل المحاضرة: القاعة محجوزة في هذا الوقت' using errcode = 'P0001';
  end if;

  if p_canceled = false then
    select exists (
      select 1 from public.lectures l
      where l.id <> target_lecture.id and l.canceled = false
        and l.day_of_week = target_lecture.day_of_week
        and l.hall_id = target_lecture.hall_id
        and target_lecture.start_at < l.end_at and target_lecture.end_at > l.start_at
    ) into hall_conflict;
    select exists (
      select 1 from public.lectures l
      where l.id <> target_lecture.id and l.canceled = false
        and l.day_of_week = target_lecture.day_of_week
        and l.instructor_id = target_lecture.instructor_id
        and target_lecture.start_at < l.end_at and target_lecture.end_at > l.start_at
    ) into instructor_conflict;
    select exists (
      select 1 from public.lectures l
      where l.id <> target_lecture.id and l.canceled = false
        and l.day_of_week = target_lecture.day_of_week
        and l.batch_id = target_lecture.batch_id
        and target_lecture.start_at < l.end_at and target_lecture.end_at > l.start_at
    ) into batch_conflict;
    if hall_conflict then conflict_message := conflict_message || 'القاعة، '; end if;
    if instructor_conflict then conflict_message := conflict_message || 'المدرس، '; end if;
    if batch_conflict then conflict_message := conflict_message || 'الدفعة، '; end if;
    if conflict_message <> 'لا يمكن إعادة تفعيل المحاضرة بسبب: ' then
      raise exception '%', rtrim(conflict_message, '، ') using errcode = 'P0001';
    end if;
  end if;

  perform set_config('app.lecture_status_reason', coalesce(clean_reason, ''), true);
  update public.lectures
  set canceled = p_canceled, updated_at = now()
  where id = target_lecture.id
  returning * into target_lecture;
  perform set_config('app.lecture_status_reason', '', true);
  return target_lecture;
end;
$$;

grant execute on function public.set_lecture_canceled_with_reason(bigint, boolean, text) to authenticated;
revoke execute on function public.set_lecture_canceled_with_reason(bigint, boolean, text) from public, anon;

-- Keep the legacy two-argument RPC used by existing Flutter clients. Its
-- implementation delegates to the new series-permission path, so the old
-- signature remains available without restoring Department Manager's global
-- cancellation capability.
create or replace function public.set_lecture_canceled(
  p_lecture_id bigint,
  p_canceled boolean
)
returns public.lectures
security definer
set search_path = public, pg_temp
language plpgsql
as $$
begin
  return public.set_lecture_canceled_with_reason(p_lecture_id, p_canceled, null);
end;
$$;

grant execute on function public.set_lecture_canceled(bigint, boolean) to authenticated;
revoke execute on function public.set_lecture_canceled(bigint, boolean) from public, anon;

create or replace function public.find_lecture_conflicts(
  p_day_of_week text,
  p_start_at time,
  p_end_at time,
  p_hall_id bigint,
  p_instructor_id bigint,
  p_batch_id bigint,
  p_exclude_id bigint default null
)
returns table (
  conflict_type text,
  lecture_id bigint,
  start_at time,
  end_at time,
  subject_id bigint,
  hall_id bigint,
  instructor_id bigint,
  batch_id bigint
)
security definer
set search_path = public, pg_temp
language plpgsql
stable
as $$
declare
  required_permission text;
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if not public.is_active_user() then
    raise exception 'profile is inactive' using errcode = '42501';
  end if;

  required_permission := case when p_exclude_id is null then 'lectures.create' else 'lectures.update' end;
  if not public.has_permission(required_permission) then
    raise exception 'the current user cannot manage this lecture' using errcode = '42501';
  end if;

  if p_day_of_week is null or btrim(p_day_of_week) = '' then
    raise exception 'p_day_of_week is required' using errcode = '22023';
  end if;
  if not exists (
    select 1
    from pg_attribute a
    join pg_type t on t.oid = a.atttypid
    join pg_enum e on e.enumtypid = t.oid
    where a.attrelid = 'public.lectures'::regclass
      and a.attname = 'day_of_week'
      and a.attnum > 0
      and not a.attisdropped
      and e.enumlabel = p_day_of_week
  ) then
    raise exception 'p_day_of_week is not a valid value of lectures.day_of_week' using errcode = '22023';
  end if;
  if p_start_at is null or p_end_at is null or p_start_at >= p_end_at then
    raise exception 'p_start_at must be earlier than p_end_at' using errcode = '22023';
  end if;
  if p_hall_id is null or p_hall_id <= 0 or not exists (select 1 from public.halls where id = p_hall_id) then
    raise exception 'p_hall_id does not reference an existing hall' using errcode = '23503';
  end if;
  if p_instructor_id is null or p_instructor_id <= 0 or not exists (select 1 from public.instructors where id = p_instructor_id) then
    raise exception 'p_instructor_id does not reference an existing instructor' using errcode = '23503';
  end if;
  if p_batch_id is null or p_batch_id <= 0 or not exists (select 1 from public.batches where id = p_batch_id) then
    raise exception 'p_batch_id does not reference an existing batch' using errcode = '23503';
  end if;
  if p_exclude_id is not null and p_exclude_id <= 0 then
    raise exception 'p_exclude_id must be positive' using errcode = '22023';
  end if;

  -- Department managers may validate only a batch in their own department. The
  -- global hall/instructor checks still prevent a shared resource collision, but
  -- the function returns only a conflict type, not another department's details.
  if public.is_department_manager() and not exists (
    select 1 from public.batches b
    where b.id = p_batch_id
      and public.department_manager_scope_allowed(b.department_id, b.level_id)
  ) then
    raise exception 'the batch is outside the current department' using errcode = '42501';
  end if;
  if p_exclude_id is not null and public.is_department_manager() and not exists (
    select 1
    from public.lectures l
    join public.batches b on b.id = l.batch_id
    where l.id = p_exclude_id
      and public.department_manager_scope_allowed(b.department_id, b.level_id)
  ) then
    raise exception 'the lecture is outside the current department' using errcode = '42501';
  end if;

  return query
    select 'hall'::text, null::bigint, null::time, null::time, null::bigint, null::bigint, null::bigint, null::bigint
    from public.lectures l
    where l.canceled = false
      and l.day_of_week::text = p_day_of_week
      and l.hall_id = p_hall_id
      and (p_exclude_id is null or l.id <> p_exclude_id)
      and p_start_at < l.end_at and p_end_at > l.start_at
    union all
    select 'instructor'::text, null::bigint, null::time, null::time, null::bigint, null::bigint, null::bigint, null::bigint
    from public.lectures l
    where l.canceled = false
      and l.day_of_week::text = p_day_of_week
      and l.instructor_id = p_instructor_id
      and (p_exclude_id is null or l.id <> p_exclude_id)
      and p_start_at < l.end_at and p_end_at > l.start_at
    union all
    select 'batch'::text, null::bigint, null::time, null::time, null::bigint, null::bigint, null::bigint, null::bigint
    from public.lectures l
    where l.canceled = false
      and l.day_of_week::text = p_day_of_week
      and l.batch_id = p_batch_id
      and (p_exclude_id is null or l.id <> p_exclude_id)
      and p_start_at < l.end_at and p_end_at > l.start_at;
end;
$$;

revoke all on function public.find_lecture_conflicts(text, time, time, bigint, bigint, bigint, bigint) from public, anon;
grant execute on function public.find_lecture_conflicts(text, time, time, bigint, bigint, bigint, bigint) to authenticated;

create or replace function public.find_all_lecture_conflicts()
returns table (
  conflict_type text,
  lecture_a_id bigint,
  lecture_b_id bigint,
  day_of_week text,
  overlap_start time,
  overlap_end time,
  resource_id bigint
)
security definer
set search_path = public, pg_temp
language plpgsql
stable
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if not public.is_active_user() or not public.has_permission('lectures.view') then
    raise exception 'the current user cannot view lecture conflicts' using errcode = '42501';
  end if;

  return query
  with visible_lectures as materialized (
    select l.*
    from public.lectures l
    where l.canceled = false
      and (
        not public.is_department_manager()
        or exists (
          select 1 from public.batches b
          where b.id = l.batch_id
            and public.department_manager_scope_allowed(b.department_id, b.level_id)
        )
      )
  )
  select 'hall'::text, a.id, b.id, a.day_of_week::text,
         greatest(a.start_at, b.start_at), least(a.end_at, b.end_at), a.hall_id
  from visible_lectures a
  join visible_lectures b
    on a.id < b.id
   and a.day_of_week = b.day_of_week
   and a.hall_id = b.hall_id
   and a.start_at < b.end_at and a.end_at > b.start_at
  union all
  select 'instructor'::text, a.id, b.id, a.day_of_week::text,
         greatest(a.start_at, b.start_at), least(a.end_at, b.end_at), a.instructor_id
  from visible_lectures a
  join visible_lectures b
    on a.id < b.id
   and a.day_of_week = b.day_of_week
   and a.instructor_id = b.instructor_id
   and a.start_at < b.end_at and a.end_at > b.start_at
  union all
  select 'batch'::text, a.id, b.id, a.day_of_week::text,
         greatest(a.start_at, b.start_at), least(a.end_at, b.end_at), a.batch_id
  from visible_lectures a
  join visible_lectures b
    on a.id < b.id
   and a.day_of_week = b.day_of_week
   and a.batch_id = b.batch_id
   and a.start_at < b.end_at and a.end_at > b.start_at;
end;
$$;

grant execute on function public.find_all_lecture_conflicts() to authenticated;
revoke execute on function public.find_all_lecture_conflicts() from public, anon;


/* PHASE1_RESERVATION_DATE_AWARE_RPC_OVERRIDES */
-- This section is date-aware and does not translate reservation_date to a
-- weekday. A specific reservation blocks only its exact date.

create or replace function public.uhms_reservation_conflict_exists(
  p_hall_id bigint,
  p_reservation_date date,
  p_day_of_week text,
  p_start_at time,
  p_end_at time,
  p_exclude_id bigint default null
)
returns boolean
security definer
set search_path = public, pg_temp
language sql
stable
as $$
  select exists (
    select 1
    from public.hall_reservations r
    where r.id is distinct from p_exclude_id
      and r.hall_id = p_hall_id
      and r.status = 'active'
      and p_start_at < r.end_at
      and p_end_at > r.start_at
      and (
        (p_reservation_date is not null and r.reservation_date = p_reservation_date)
        or (p_reservation_date is not null and r.reservation_date is null and r.day_of_week = case extract(dow from p_reservation_date)::integer when 0 then 'احد' when 1 then 'أثنين' when 2 then 'ثلاثاء' when 3 then 'اربعاء' when 4 then 'خميس' when 5 then 'جمعة' when 6 then 'سبت' end)
        or (p_reservation_date is null and r.reservation_date is not null and public.uhms_date_matches_lecture_day(r.reservation_date, p_day_of_week))
        or (p_reservation_date is null and r.reservation_date is null and r.day_of_week = p_day_of_week)
      )
  );
$$;

revoke all on function public.uhms_reservation_conflict_exists(bigint, date, text, time, time, bigint) from public, anon, authenticated;

-- Database-level guard for reservation writes. The RPCs below already validate
-- these rules, but this trigger protects direct/privileged table writes too and
-- uses the same advisory lock as lecture writes to prevent a cross-table race.
create or replace function public.uhms_validate_hall_reservation_conflicts()
returns trigger
security definer
set search_path = public, pg_temp
language plpgsql
as $$
begin
  if new.status <> 'active' then
    return new;
  end if;
  if new.reservation_date is null
     and not public.uhms_enum_value_exists('public.lectures'::regclass, 'day_of_week', new.day_of_week) then
    raise exception 'day_of_week is not a valid value' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(918273645::bigint);

  if exists (
    select 1 from public.halls h
    where h.id = new.hall_id and h.booking = true
  ) then
    raise exception 'لا يمكن حفظ الحجز لأن القاعة غير متاحة إداريًا' using errcode = 'P0001';
  end if;

  if public.uhms_reservation_conflict_exists(
    new.hall_id, new.reservation_date, new.day_of_week,
    new.start_at, new.end_at, new.id
  ) then
    raise exception 'لا يمكن حفظ الحجز: يوجد حجز آخر متداخل للقاعة' using errcode = 'P0001';
  end if;

  if exists (
    select 1
    from public.lectures l
    where l.canceled = false
      and l.hall_id = new.hall_id
      and new.start_at < l.end_at
      and new.end_at > l.start_at
      and (
        (new.reservation_date is null and l.day_of_week::text = new.day_of_week)
        or (
          new.reservation_date is not null
          and public.uhms_date_matches_lecture_day(new.reservation_date, l.day_of_week::text)
          and not exists (
            select 1
            from public.lecture_occurrence_overrides o
            where o.lecture_id = l.id
              and o.occurrence_date = new.reservation_date
          )
        )
      )
  ) then
    raise exception 'لا يمكن حفظ الحجز: القاعة مشغولة بمحاضرة في هذا الوقت' using errcode = 'P0001';
  end if;

  return new;
end;
$$;

revoke all on function public.uhms_validate_hall_reservation_conflicts() from public, anon, authenticated;

do $$
begin
  if not exists (
    select 1
    from pg_trigger
    where tgname = 'uhms_phase1_hall_reservation_conflict_guard'
      and tgrelid = 'public.hall_reservations'::regclass
      and not tgisinternal
  ) then
    execute 'create trigger uhms_phase1_hall_reservation_conflict_guard
      before insert or update on public.hall_reservations
      for each row execute function public.uhms_validate_hall_reservation_conflicts()';
  end if;
end;
$$;

create or replace function public.find_hall_reservation_conflicts_v2(
  p_hall_id bigint,
  p_reservation_date date,
  p_day_of_week text,
  p_start_at time,
  p_end_at time,
  p_exclude_id bigint default null
)
returns table(conflict_type text, conflict_id bigint, conflict_start time, conflict_end time)
security definer
set search_path = public, pg_temp
language plpgsql
stable
as $$
declare required_permission text;
begin
  if auth.uid() is null or not public.is_active_user() then raise exception 'not authenticated' using errcode = '28000'; end if;
  required_permission := case when p_exclude_id is null then 'hall_reservations.create' else 'hall_reservations.update' end;
  if not public.has_permission(required_permission) then raise exception 'the current user cannot manage hall reservations' using errcode = '42501'; end if;
  if p_hall_id is null or not exists (select 1 from public.halls where id = p_hall_id) then raise exception 'hall does not exist' using errcode = '23503'; end if;
  if (p_reservation_date is null) = (p_day_of_week is null or btrim(p_day_of_week) = '') then raise exception 'provide either reservation_date or day_of_week, but not both' using errcode = '22023'; end if;
  if p_day_of_week is not null and not public.uhms_enum_value_exists('public.lectures'::regclass, 'day_of_week', p_day_of_week) then raise exception 'day_of_week is not a valid value' using errcode = '22023'; end if;
  if p_start_at is null or p_end_at is null or p_start_at >= p_end_at then raise exception 'start_at must be earlier than end_at' using errcode = '22023'; end if;
  return query
    select 'reservation'::text, r.id, r.start_at, r.end_at
    from public.hall_reservations r
    where r.id is distinct from p_exclude_id and r.hall_id = p_hall_id and r.status = 'active'
      and p_start_at < r.end_at and p_end_at > r.start_at
      and ((p_reservation_date is not null and r.reservation_date = p_reservation_date)
        or (p_reservation_date is not null and r.reservation_date is null and public.uhms_date_matches_lecture_day(p_reservation_date, r.day_of_week))
        or (p_reservation_date is null and r.reservation_date is not null and public.uhms_date_matches_lecture_day(r.reservation_date, p_day_of_week))
        or (p_reservation_date is null and r.reservation_date is null and r.day_of_week = p_day_of_week))
    union all
    select 'lecture'::text, l.id, l.start_at, l.end_at
    from public.lectures l
    where l.canceled = false and l.hall_id = p_hall_id
      and p_start_at < l.end_at and p_end_at > l.start_at
      and ((p_reservation_date is null and l.day_of_week::text = p_day_of_week)
        or (p_reservation_date is not null and public.uhms_date_matches_lecture_day(p_reservation_date, l.day_of_week::text)
          and not exists (select 1 from public.lecture_occurrence_overrides o where o.lecture_id = l.id and o.occurrence_date = p_reservation_date)));
end;
$$;

grant execute on function public.find_hall_reservation_conflicts_v2(bigint, date, text, time, time, bigint) to authenticated;
revoke execute on function public.find_hall_reservation_conflicts_v2(bigint, date, text, time, time, bigint) from public, anon;

create or replace function public.save_hall_reservation(p_reservation_id bigint, p_payload jsonb)
returns public.hall_reservations
security definer
set search_path = public, pg_temp
language plpgsql
as $$
declare
  current_reservation public.hall_reservations;
  saved_reservation public.hall_reservations;
  hall_value bigint;
  reservation_date_value date;
  day_value text;
  start_value time;
  end_value time;
  reason_value text;
  notes_value text;
  required_permission text;
begin
  if auth.uid() is null or not public.is_active_user() then raise exception 'not authenticated' using errcode = '28000'; end if;
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then raise exception 'reservation payload must be a JSON object' using errcode = '22023'; end if;
  required_permission := case when p_reservation_id is null then 'hall_reservations.create' else 'hall_reservations.update' end;
  if not public.has_permission(required_permission) then raise exception 'the current user cannot manage hall reservations' using errcode = '42501'; end if;
  perform pg_advisory_xact_lock(918273645::bigint);
  if p_reservation_id is not null then
    select * into current_reservation from public.hall_reservations where id = p_reservation_id for update;
    if current_reservation.id is null then raise exception 'reservation was not found' using errcode = 'P0002'; end if;
  end if;
  if (p_payload ->> 'hall_id') !~ '^[1-9][0-9]*$' then raise exception 'hall_id must be a positive integer' using errcode = '22023'; end if;
  hall_value := (p_payload ->> 'hall_id')::bigint;
  if not exists (select 1 from public.halls where id = hall_value) then raise exception 'hall does not exist' using errcode = '23503'; end if;
  if p_payload ? 'reservation_date' and jsonb_typeof(p_payload -> 'reservation_date') = 'string' and btrim(p_payload ->> 'reservation_date') <> '' then
    begin reservation_date_value := (p_payload ->> 'reservation_date')::date; exception when others then raise exception 'reservation_date must be a valid date' using errcode = '22023'; end;
  else reservation_date_value := null;
  end if;
  day_value := nullif(btrim(p_payload ->> 'day_of_week'), '');
  if (reservation_date_value is null) = (day_value is null) then raise exception 'provide either reservation_date or day_of_week, but not both' using errcode = '22023'; end if;
  if day_value is not null and not public.uhms_enum_value_exists('public.lectures'::regclass, 'day_of_week', day_value) then raise exception 'day_of_week is not a valid value' using errcode = '22023'; end if;
  begin start_value := (p_payload ->> 'start_at')::time; end_value := (p_payload ->> 'end_at')::time; exception when others then raise exception 'start_at and end_at must be valid times' using errcode = '22023'; end;
  if start_value is null or end_value is null or start_value >= end_value then raise exception 'start_at must be earlier than end_at' using errcode = '22023'; end if;
  reason_value := nullif(btrim(p_payload ->> 'reason'), '');
  notes_value := nullif(btrim(p_payload ->> 'notes'), '');
  if char_length(reason_value) > 500 or char_length(notes_value) > 2000 then raise exception 'reason or notes is too long' using errcode = '22023'; end if;
  if exists (select 1 from public.halls where id = hall_value and booking = true) then raise exception 'لا يمكن حجز القاعة لأنها غير متاحة إداريًا' using errcode = 'P0001'; end if;
  if p_reservation_id is null or current_reservation.status = 'active' then
    if public.uhms_reservation_conflict_exists(hall_value, reservation_date_value, day_value, start_value, end_value, p_reservation_id) then raise exception 'لا يمكن حفظ الحجز: يوجد حجز آخر متداخل للقاعة' using errcode = 'P0001'; end if;
    if exists (
      select 1 from public.lectures l
      where l.canceled = false and l.hall_id = hall_value and start_value < l.end_at and end_value > l.start_at
        and ((reservation_date_value is null and l.day_of_week::text = day_value)
          or (reservation_date_value is not null and public.uhms_date_matches_lecture_day(reservation_date_value, l.day_of_week::text)
            and not exists (select 1 from public.lecture_occurrence_overrides o where o.lecture_id = l.id and o.occurrence_date = reservation_date_value)))
    ) then raise exception 'لا يمكن حفظ الحجز: القاعة مشغولة بمحاضرة في هذا الوقت' using errcode = 'P0001'; end if;
  end if;
  if p_reservation_id is null then
    insert into public.hall_reservations(hall_id,reservation_date,day_of_week,start_at,end_at,status,reason,notes,created_by,updated_by)
    values (hall_value,reservation_date_value,day_value,start_value,end_value,'active',reason_value,notes_value,auth.uid(),auth.uid()) returning * into saved_reservation;
  else
    update public.hall_reservations set hall_id=hall_value,reservation_date=reservation_date_value,day_of_week=day_value,start_at=start_value,end_at=end_value,reason=reason_value,notes=notes_value,updated_by=auth.uid(),updated_at=now() where id=p_reservation_id returning * into saved_reservation;
  end if;
  return saved_reservation;
end;
$$;

grant execute on function public.save_hall_reservation(bigint, jsonb) to authenticated;
revoke execute on function public.save_hall_reservation(bigint, jsonb) from public, anon;

create or replace function public.set_hall_reservation_status(p_reservation_id bigint, p_status text, p_reason text default null)
returns public.hall_reservations
security definer
set search_path = public, pg_temp
language plpgsql
as $$
declare
  target_reservation public.hall_reservations;
  updated_reservation public.hall_reservations;
  clean_reason text := nullif(btrim(coalesce(p_reason, '')), '');
  conflict_on_lecture boolean;
begin
  if auth.uid() is null or not public.is_active_user() then raise exception 'not authenticated' using errcode = '28000'; end if;
  if not public.has_permission('hall_reservations.cancel') then raise exception 'the current user cannot change reservation status' using errcode = '42501'; end if;
  if p_reservation_id is null or p_reservation_id <= 0 or p_status not in ('active','canceled') then raise exception 'reservation id or status is invalid' using errcode = '22023'; end if;
  if clean_reason is not null and char_length(clean_reason) > 500 then raise exception 'reason must not exceed 500 characters' using errcode = '22023'; end if;
  perform pg_advisory_xact_lock(918273645::bigint);
  select * into target_reservation from public.hall_reservations where id=p_reservation_id for update;
  if target_reservation.id is null then raise exception 'reservation was not found' using errcode = 'P0002'; end if;
  if target_reservation.status = p_status then return target_reservation; end if;
  if p_status = 'active' then
    if exists (select 1 from public.halls where id=target_reservation.hall_id and booking=true) then raise exception 'لا يمكن تفعيل الحجز لأن القاعة غير متاحة إداريًا' using errcode = 'P0001'; end if;
    if public.uhms_reservation_conflict_exists(target_reservation.hall_id,target_reservation.reservation_date,target_reservation.day_of_week,target_reservation.start_at,target_reservation.end_at,target_reservation.id) then raise exception 'لا يمكن تفعيل الحجز: يوجد حجز آخر متداخل' using errcode = 'P0001'; end if;
    conflict_on_lecture := exists (
      select 1 from public.lectures l
      where l.canceled=false and l.hall_id=target_reservation.hall_id and target_reservation.start_at < l.end_at and target_reservation.end_at > l.start_at
        and ((target_reservation.reservation_date is null and l.day_of_week::text=target_reservation.day_of_week)
          or (target_reservation.reservation_date is not null and public.uhms_date_matches_lecture_day(target_reservation.reservation_date,l.day_of_week::text) and not exists (select 1 from public.lecture_occurrence_overrides o where o.lecture_id=l.id and o.occurrence_date=target_reservation.reservation_date)))
    );
    if conflict_on_lecture then raise exception 'لا يمكن تفعيل الحجز: القاعة مشغولة بمحاضرة في هذا الوقت' using errcode = 'P0001'; end if;
  end if;
  update public.hall_reservations set status=p_status,reason=coalesce(clean_reason,reason),updated_by=auth.uid(),updated_at=now() where id=target_reservation.id returning * into updated_reservation;
  return updated_reservation;
end;
$$;

grant execute on function public.set_hall_reservation_status(bigint, text, text) to authenticated;
revoke execute on function public.set_hall_reservation_status(bigint, text, text) from public, anon;
