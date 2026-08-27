-- University Hall Management System security functions.
-- Run after schema.sql and before policies.sql.
-- This file never changes, deletes, or truncates data in the academic tables.

-- One index per conflict dimension is more useful than one index beginning with
-- (day, hall, instructor, batch): PostgreSQL can use each partial index for the
-- corresponding UNION branch while ignoring canceled lectures.
create index if not exists lectures_conflict_hall_idx
on public.lectures(day_of_week, hall_id, start_at, end_at)
where canceled = false;

create index if not exists lectures_conflict_instructor_idx
on public.lectures(day_of_week, instructor_id, start_at, end_at)
where canceled = false;

create index if not exists lectures_conflict_batch_idx
on public.lectures(day_of_week, batch_id, start_at, end_at)
where canceled = false;

-- Authorization helpers. They are intentionally small, stable, and SECURITY DEFINER
-- so policies do not recursively evaluate profiles/role_permissions RLS.
create or replace function public.is_active_user()
returns boolean
security definer
set search_path = public, pg_temp
language sql
stable
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and is_active = true
  );
$$;

create or replace function public.current_role_key()
returns text
security definer
set search_path = public, pg_temp
language sql
stable
as $$
  select role from public.profiles
  where id = auth.uid() and is_active = true
  limit 1;
$$;

create or replace function public.current_department_id()
returns bigint
security definer
set search_path = public, pg_temp
language sql
stable
as $$
  select department_id from public.profiles
  where id = auth.uid() and is_active = true
  limit 1;
$$;

create or replace function public.is_super_admin()
returns boolean
security definer
set search_path = public, pg_temp
language sql
stable
as $$
  select public.current_role_key() = 'super_admin';
$$;

create or replace function public.has_permission(requested_permission text)
returns boolean
security definer
set search_path = public, pg_temp
language sql
stable
as $$
  select exists (
    select 1
    from public.profiles p
    left join public.role_permissions rp
      on rp.role_key = p.role
     and rp.permission_key = requested_permission
    where p.id = auth.uid()
      and p.is_active = true
      and (p.role = 'super_admin' or rp.permission_key is not null)
  );
$$;

create or replace function public.is_department_manager()
returns boolean
security definer
set search_path = public, pg_temp
language sql
stable
as $$
  select public.current_role_key() = 'department_manager';
$$;

revoke all on function public.is_active_user() from public, anon;
revoke all on function public.current_role_key() from public, anon;
revoke all on function public.current_department_id() from public, anon;
revoke all on function public.is_super_admin() from public, anon;
revoke all on function public.has_permission(text) from public, anon;
revoke all on function public.is_department_manager() from public, anon;
grant execute on function public.is_active_user() to authenticated;
grant execute on function public.current_role_key() to authenticated;
grant execute on function public.current_department_id() to authenticated;
grant execute on function public.is_super_admin() to authenticated;
grant execute on function public.has_permission(text) to authenticated;
grant execute on function public.is_department_manager() to authenticated;

-- A user can update only the display name of their own active profile. There is no
-- direct UPDATE grant on profiles; this RPC is the only client-side path.
create or replace function public.update_my_profile(new_full_name text)
returns public.profiles
security definer
set search_path = public, pg_temp
language plpgsql
as $$
declare
  clean_name text;
  updated_profile public.profiles;
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  if not public.is_active_user() then
    raise exception 'profile is inactive' using errcode = '42501';
  end if;

  clean_name := btrim(coalesce(new_full_name, ''));
  if char_length(clean_name) < 2 then
    raise exception 'full_name must contain at least 2 characters' using errcode = '22023';
  end if;
  if char_length(clean_name) > 120 then
    raise exception 'full_name must not exceed 120 characters' using errcode = '22023';
  end if;

  update public.profiles
  set full_name = clean_name,
      updated_at = now()
  where id = auth.uid()
    and is_active = true
  returning * into updated_profile;

  if updated_profile.id is null then
    raise exception 'active profile was not found' using errcode = 'P0002';
  end if;
  return updated_profile;
end;
$$;

revoke all on function public.update_my_profile(text) from public, anon;
grant execute on function public.update_my_profile(text) to authenticated;

-- Administrative profile mutation. A browser can call this function, but only an
-- active super_admin can pass the authorization check. The JSON patch intentionally
-- whitelists editable fields; email, id, created_at and unknown fields are rejected.
create or replace function public.admin_update_profile(
  p_user_id uuid,
  p_patch jsonb
)
returns public.profiles
security definer
set search_path = public, pg_temp
language plpgsql
as $$
declare
  target_profile public.profiles;
  updated_profile public.profiles;
  next_name text;
  next_role text;
  next_department_id bigint;
  next_active boolean;
  changed_role boolean := false;
  changed_active boolean := false;
  super_admin_count integer;
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if not public.is_active_user() or not public.is_super_admin() then
    raise exception 'only an active super_admin may manage profiles' using errcode = '42501';
  end if;
  if p_user_id is null then
    raise exception 'p_user_id is required' using errcode = '22023';
  end if;
  if p_patch is null or jsonb_typeof(p_patch) <> 'object' or p_patch = '{}'::jsonb then
    raise exception 'p_patch must be a non-empty JSON object' using errcode = '22023';
  end if;

  if exists (
    select 1
    from jsonb_object_keys(p_patch) as patch_keys(field_name)
    where patch_keys.field_name not in ('full_name', 'role', 'department_id', 'is_active')
  ) then
    raise exception 'p_patch contains a field that cannot be changed' using errcode = '22023';
  end if;

  select * into target_profile
  from public.profiles
  where id = p_user_id
  for update;
  if target_profile.id is null then
    raise exception 'profile was not found' using errcode = 'P0002';
  end if;

  -- Do not let an administrator lock their own account or remove their own role.
  if p_user_id = auth.uid() and (p_patch ? 'role' or p_patch ? 'is_active') then
    raise exception 'you cannot change your own role or active status' using errcode = '42501';
  end if;

  if p_patch ? 'full_name' then
    if jsonb_typeof(p_patch -> 'full_name') <> 'string' then
      raise exception 'full_name must be a string' using errcode = '22023';
    end if;
    next_name := btrim(p_patch ->> 'full_name');
    if char_length(next_name) < 2 or char_length(next_name) > 120 then
      raise exception 'full_name must contain 2 to 120 characters' using errcode = '22023';
    end if;
  end if;

  if p_patch ? 'role' then
    if jsonb_typeof(p_patch -> 'role') <> 'string' then
      raise exception 'role must be a string' using errcode = '22023';
    end if;
    next_role := p_patch ->> 'role';
    if not exists (select 1 from public.roles where key = next_role) then
      raise exception 'role does not exist' using errcode = '23503';
    end if;
    changed_role := next_role <> target_profile.role;
  end if;

  if p_patch ? 'department_id' then
    if jsonb_typeof(p_patch -> 'department_id') not in ('number', 'null') then
      raise exception 'department_id must be a number or null' using errcode = '22023';
    end if;
    if jsonb_typeof(p_patch -> 'department_id') = 'number' then
      next_department_id := (p_patch ->> 'department_id')::bigint;
      if next_department_id <= 0 or not exists (select 1 from public.departments where id = next_department_id) then
        raise exception 'department_id does not reference an existing department' using errcode = '23503';
      end if;
    else
      next_department_id := null;
    end if;
  end if;

  if p_patch ? 'is_active' then
    if jsonb_typeof(p_patch -> 'is_active') <> 'boolean' then
      raise exception 'is_active must be boolean' using errcode = '22023';
    end if;
    next_active := (p_patch ->> 'is_active')::boolean;
    changed_active := next_active <> target_profile.is_active;
  end if;

  -- Prevent accidentally removing the final active Super Admin.
  if target_profile.role = 'super_admin' and (changed_role or (changed_active and next_active = false)) then
    select count(*) into super_admin_count
    from public.profiles
    where role = 'super_admin' and is_active = true;
    if super_admin_count <= 1 then
      raise exception 'at least one active super_admin must remain' using errcode = '42501';
    end if;
  end if;

  update public.profiles
  set full_name = case when p_patch ? 'full_name' then next_name else full_name end,
      role = case when p_patch ? 'role' then next_role else role end,
      department_id = case when p_patch ? 'department_id' then next_department_id else department_id end,
      is_active = case when p_patch ? 'is_active' then next_active else is_active end,
      updated_at = now()
  where id = p_user_id
  returning * into updated_profile;

  return updated_profile;
end;
$$;

revoke all on function public.admin_update_profile(uuid, jsonb) from public, anon;
grant execute on function public.admin_update_profile(uuid, jsonb) to authenticated;

-- Role-permission changes are also RPC-only. The super_admin role itself is kept
-- fully authorized by has_permission(), so its matrix cannot be disabled by mistake.
create or replace function public.set_role_permission(
  p_role_key text,
  p_permission_key text,
  p_enabled boolean
)
returns void
security definer
set search_path = public, pg_temp
language plpgsql
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if not public.is_active_user() or not public.is_super_admin() then
    raise exception 'only an active super_admin may manage permissions' using errcode = '42501';
  end if;
  if p_role_key is null or p_permission_key is null or p_enabled is null then
    raise exception 'role, permission and enabled are required' using errcode = '22023';
  end if;
  if p_role_key = 'super_admin' then
    raise exception 'super_admin permissions are always complete' using errcode = '42501';
  end if;
  if not exists (select 1 from public.roles where key = p_role_key) then
    raise exception 'role does not exist' using errcode = '23503';
  end if;
  if not exists (select 1 from public.permissions where key = p_permission_key) then
    raise exception 'permission does not exist' using errcode = '23503';
  end if;

  if p_enabled then
    insert into public.role_permissions(role_key, permission_key)
    values (p_role_key, p_permission_key)
    on conflict (role_key, permission_key) do nothing;
  else
    delete from public.role_permissions
    where role_key = p_role_key and permission_key = p_permission_key;
  end if;
end;
$$;

revoke all on function public.set_role_permission(text, text, boolean) from public, anon;
grant execute on function public.set_role_permission(text, text, boolean) to authenticated;

-- The actual enum type name is intentionally not guessed. The RPC accepts text at
-- the PostgREST boundary, validates it against the enum attached to lectures.day_of_week,
-- and compares using its textual representation. This remains compatible with the
-- existing Flutter schema even when the enum type has a project-specific name.
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
    select 1 from public.batches
    where id = p_batch_id and department_id = public.current_department_id()
  ) then
    raise exception 'the batch is outside the current department' using errcode = '42501';
  end if;
  if p_exclude_id is not null and public.is_department_manager() and not exists (
    select 1
    from public.lectures l
    join public.batches b on b.id = l.batch_id
    where l.id = p_exclude_id and b.department_id = public.current_department_id()
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

-- Lifecycle RPC for cancellation and reactivation. It keeps the state change
-- behind the cancel permission and rechecks all conflicts before reactivation.
create or replace function public.set_lecture_canceled(
  p_lecture_id bigint,
  p_canceled boolean
)
returns public.lectures
security definer
set search_path = public, pg_temp
language plpgsql
as $$
declare
  target_lecture public.lectures;
  hall_conflict boolean := false;
  instructor_conflict boolean := false;
  batch_conflict boolean := false;
  conflict_message text := 'لا يمكن إعادة تفعيل المحاضرة بسبب: ';
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if not public.is_active_user() or not public.has_permission('lectures.cancel') then
    raise exception 'the current user cannot change lecture cancellation state' using errcode = '42501';
  end if;
  if p_lecture_id is null or p_lecture_id <= 0 then
    raise exception 'p_lecture_id must be positive' using errcode = '22023';
  end if;
  if p_canceled is null then
    raise exception 'p_canceled is required' using errcode = '22023';
  end if;

  select * into target_lecture
  from public.lectures
  where id = p_lecture_id
  for update;

  if target_lecture.id is null then
    raise exception 'lecture was not found' using errcode = 'P0002';
  end if;

  if public.is_department_manager() and not exists (
    select 1
    from public.batches b
    where b.id = target_lecture.batch_id
      and b.department_id = public.current_department_id()
  ) then
    raise exception 'the lecture is outside the current department' using errcode = '42501';
  end if;

  -- Idempotent request: do not touch updated_at if the requested state already exists.
  if target_lecture.canceled = p_canceled then
    return target_lecture;
  end if;

  -- Cancellation does not need a conflict check. Reactivation does.
  if p_canceled = false then
    select exists (
      select 1 from public.lectures l
      where l.id <> target_lecture.id
        and l.canceled = false
        and l.day_of_week::text = target_lecture.day_of_week::text
        and l.hall_id = target_lecture.hall_id
        and target_lecture.start_at < l.end_at
        and target_lecture.end_at > l.start_at
    ) into hall_conflict;

    select exists (
      select 1 from public.lectures l
      where l.id <> target_lecture.id
        and l.canceled = false
        and l.day_of_week::text = target_lecture.day_of_week::text
        and l.instructor_id = target_lecture.instructor_id
        and target_lecture.start_at < l.end_at
        and target_lecture.end_at > l.start_at
    ) into instructor_conflict;

    select exists (
      select 1 from public.lectures l
      where l.id <> target_lecture.id
        and l.canceled = false
        and l.day_of_week::text = target_lecture.day_of_week::text
        and l.batch_id = target_lecture.batch_id
        and target_lecture.start_at < l.end_at
        and target_lecture.end_at > l.start_at
    ) into batch_conflict;

    if hall_conflict or instructor_conflict or batch_conflict then
      if hall_conflict then conflict_message := conflict_message || 'القاعة، '; end if;
      if instructor_conflict then conflict_message := conflict_message || 'المدرس، '; end if;
      if batch_conflict then conflict_message := conflict_message || 'الدفعة، '; end if;
      raise exception '%', rtrim(conflict_message, '، ') using errcode = 'P0001';
    end if;
  end if;

  update public.lectures
  set canceled = p_canceled,
      updated_at = now()
  where id = target_lecture.id
  returning * into target_lecture;

  return target_lecture;
end;
$$;

revoke all on function public.set_lecture_canceled(bigint, boolean) from public, anon;
grant execute on function public.set_lecture_canceled(bigint, boolean) to authenticated;

-- === Schedule hardening: status history, atomic writes, and a global conflict guard ===
-- These additions are additive and preserve the existing lectures columns.

create table if not exists public.lecture_status_history (
  id bigint generated always as identity primary key,
  lecture_id bigint not null references public.lectures(id) on delete restrict,
  old_canceled boolean not null,
  new_canceled boolean not null,
  changed_by uuid references auth.users(id) on delete set null,
  changed_at timestamptz not null default now(),
  reason text,
  constraint lecture_status_history_state_check check (old_canceled is distinct from new_canceled),
  constraint lecture_status_history_reason_length_check check (reason is null or char_length(reason) <= 500)
);

create index if not exists lecture_status_history_lecture_idx
on public.lecture_status_history(lecture_id, changed_at desc);

create index if not exists lecture_status_history_changed_by_idx
on public.lecture_status_history(changed_by, changed_at desc);

grant select on public.lecture_status_history to authenticated;
revoke insert, update, delete, truncate on public.lecture_status_history from anon, authenticated;
alter table public.lecture_status_history enable row level security;

drop policy if exists uhms_lecture_status_history_select on public.lecture_status_history;
create policy uhms_lecture_status_history_select
on public.lecture_status_history
for select to authenticated
using (
  public.has_permission('lectures.view')
  and exists (
    select 1
    from public.lectures l
    where l.id = lecture_status_history.lecture_id
      and (
        not public.is_department_manager()
        or exists (
          select 1 from public.batches b
          where b.id = l.batch_id
            and b.department_id = public.current_department_id()
        )
      )
  )
);

create or replace function public.uhms_record_lecture_status_history()
returns trigger
security definer
set search_path = public, pg_temp
language plpgsql
as $$
declare
  status_reason text;
begin
  if old.canceled is distinct from new.canceled then
    status_reason := nullif(left(current_setting('app.lecture_status_reason', true), 500), '');
    insert into public.lecture_status_history (
      lecture_id, old_canceled, new_canceled, changed_by, reason
    ) values (
      new.id, old.canceled, new.canceled, auth.uid(), status_reason
    );
  end if;
  return new;
end;
$$;

revoke all on function public.uhms_record_lecture_status_history() from public, anon, authenticated;

do $$
begin
  if not exists (
    select 1 from pg_trigger
    where tgname = 'uhms_lecture_status_history_trigger'
      and tgrelid = 'public.lectures'::regclass
      and not tgisinternal
  ) then
    execute 'create trigger uhms_lecture_status_history_trigger after update of canceled on public.lectures for each row execute function public.uhms_record_lecture_status_history()';
  end if;
end;
$$;

-- Server-side guard for all direct INSERT/UPDATE paths, including Flutter or a
-- future client. It uses one transaction-level advisory lock to close the race
-- between two concurrent schedule writes performed through this project.
create or replace function public.uhms_validate_lecture_conflicts()
returns trigger
security definer
set search_path = public, pg_temp
language plpgsql
as $$
begin
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

  -- Canceled lectures do not reserve resources.
  if new.canceled then
    return new;
  end if;

  perform pg_advisory_xact_lock(918273645::bigint);

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

do $$
begin
  if not exists (
    select 1 from pg_trigger
    where tgname = 'uhms_lectures_conflict_guard'
      and tgrelid = 'public.lectures'::regclass
      and not tgisinternal
  ) then
    execute 'create trigger uhms_lectures_conflict_guard before insert or update on public.lectures for each row execute function public.uhms_validate_lecture_conflicts()';
  end if;
end;
$$;

-- Validate an enum value without guessing the project's enum type name.
create or replace function public.uhms_enum_value_exists(
  p_table regclass,
  p_column name,
  p_value text
)
returns boolean
security definer
set search_path = public, pg_temp
language sql
stable
as $$
  select exists (
    select 1
    from pg_attribute a
    join pg_type t on t.oid = a.atttypid
    join pg_enum e on e.enumtypid = t.oid
    where a.attrelid = p_table
      and a.attname = p_column
      and a.attnum > 0
      and not a.attisdropped
      and e.enumlabel = p_value
  );
$$;

revoke all on function public.uhms_enum_value_exists(regclass, name, text) from public, anon;
grant execute on function public.uhms_enum_value_exists(regclass, name, text) to authenticated;

-- Atomic create/update RPC. The enum casts are built from pg_catalog, so the
-- project-specific day/group type names are never hard-coded.
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
  if public.is_department_manager() and not exists (
    select 1 from public.batches
    where id = batch_value and department_id = public.current_department_id()
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

-- Reason-aware lifecycle RPC. The old two-argument RPC is kept as a compatibility
-- wrapper below; both paths generate status history via the trigger.
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
  if not public.is_active_user() or not public.has_permission('lectures.cancel') then
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
      and b.department_id = public.current_department_id()
  ) then
    raise exception 'the lecture is outside the current department' using errcode = '42501';
  end if;
  if target_lecture.canceled = p_canceled then
    return target_lecture;
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

-- Conflict Center RPC. Department Managers see conflicts among their own
-- department's lectures; global managers see the full shared schedule.
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
            and b.department_id = public.current_department_id()
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
