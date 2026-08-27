-- University Hall Management System: Department Manager scopes and hall reservations.
-- Incremental, additive migration for an existing installation.
-- Does not drop/truncate/alter existing academic columns or delete rows.
-- Run after schema.sql, functions.sql, policies.sql, and schedule_hardening.sql.

/* -------------------------------------------------------------------------- */
/* 1. Permission catalog                                                      */
/* -------------------------------------------------------------------------- */

insert into public.permissions(key, label_ar, resource, action) values
  ('hall_reservations.view', 'عرض حجوزات القاعات', 'hall_reservations', 'view'),
  ('hall_reservations.create', 'إنشاء حجوزات القاعات', 'hall_reservations', 'create'),
  ('hall_reservations.update', 'تعديل حجوزات القاعات', 'hall_reservations', 'update'),
  ('hall_reservations.cancel', 'إلغاء حجوزات القاعات', 'hall_reservations', 'cancel')
on conflict (key) do update set label_ar = excluded.label_ar, resource = excluded.resource, action = excluded.action;

insert into public.role_permissions(role_key, permission_key)
select 'admin', p.key from public.permissions p
where p.key not like 'users.%' and p.key not like 'roles.%'
on conflict do nothing;

insert into public.role_permissions(role_key, permission_key) values
  ('schedule_manager', 'hall_reservations.view'),
  ('schedule_manager', 'hall_reservations.create'),
  ('schedule_manager', 'hall_reservations.update'),
  ('schedule_manager', 'hall_reservations.cancel'),
  ('department_manager', 'hall_reservations.view'),
  ('viewer', 'hall_reservations.view')
on conflict do nothing;

/* -------------------------------------------------------------------------- */
/* 2. Department Manager scopes                                               */
/* -------------------------------------------------------------------------- */

create table if not exists public.department_manager_scopes (
  id bigint generated always as identity primary key,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  department_id bigint not null references public.departments(id) on delete cascade,
  level_id bigint references public.levels(id) on delete cascade,
  created_at timestamptz not null default now()
);

create unique index if not exists department_manager_scopes_all_unique
on public.department_manager_scopes(profile_id, department_id)
where level_id is null;

create unique index if not exists department_manager_scopes_level_unique
on public.department_manager_scopes(profile_id, department_id, level_id)
where level_id is not null;

create index if not exists department_manager_scopes_profile_idx
on public.department_manager_scopes(profile_id);

create index if not exists department_manager_scopes_department_level_idx
on public.department_manager_scopes(department_id, level_id);

grant select on public.department_manager_scopes to authenticated;
revoke insert, update, delete, truncate on public.department_manager_scopes from anon, authenticated;
alter table public.department_manager_scopes enable row level security;

drop policy if exists uhms_department_manager_scopes_select on public.department_manager_scopes;
create policy uhms_department_manager_scopes_select
on public.department_manager_scopes
for select to authenticated
using (profile_id = auth.uid() or public.is_super_admin());

-- A scope with level_id NULL means all levels of that department. If an old
-- Department Manager has no rows yet, department_id remains a backwards-
-- compatible fallback and grants the whole legacy department.
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
declare
  has_explicit_scopes boolean;
begin
  if auth.uid() is null or not public.is_active_user() then
    return false;
  end if;
  if public.current_role_key() <> 'department_manager' then
    return true;
  end if;

  select exists (
    select 1 from public.department_manager_scopes s
    where s.profile_id = auth.uid()
  ) into has_explicit_scopes;

  if not has_explicit_scopes then
    return p_department_id = public.current_department_id();
  end if;

  return exists (
    select 1
    from public.department_manager_scopes s
    where s.profile_id = auth.uid()
      and s.department_id = p_department_id
      and (p_level_id is null or s.level_id is null or s.level_id = p_level_id)
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
declare
  has_explicit_scopes boolean;
begin
  if auth.uid() is null or not public.is_active_user() then
    return false;
  end if;
  if public.current_role_key() <> 'department_manager' then
    return true;
  end if;

  select exists (
    select 1 from public.department_manager_scopes s
    where s.profile_id = auth.uid()
  ) into has_explicit_scopes;

  if not has_explicit_scopes then
    return true;
  end if;

  return exists (
    select 1 from public.department_manager_scopes s
    where s.profile_id = auth.uid()
      and (s.level_id is null or s.level_id = p_level_id)
  );
end;
$$;

revoke all on function public.department_manager_scope_allowed(bigint, bigint) from public, anon;
revoke all on function public.department_manager_level_allowed(bigint) from public, anon;
grant execute on function public.department_manager_scope_allowed(bigint, bigint) to authenticated;
grant execute on function public.department_manager_level_allowed(bigint) to authenticated;

-- Super Admin-only RPC to replace all scopes for one user atomically.
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
  scopes_count integer;
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

  select * into target_profile from public.profiles where id = p_user_id;
  if target_profile.id is null then
    raise exception 'profile was not found' using errcode = 'P0002';
  end if;
  if target_profile.role <> 'department_manager' and jsonb_array_length(p_scopes) > 0 then
    raise exception 'scopes can only be assigned to a department_manager' using errcode = '22023';
  end if;

  scopes_count := jsonb_array_length(p_scopes);
  for scope_item in select value from jsonb_array_elements(p_scopes)
  loop
    if jsonb_typeof(scope_item) <> 'object'
       or not (scope_item ? 'department_id')
       or jsonb_typeof(scope_item -> 'department_id') <> 'number' then
      raise exception 'each scope needs a numeric department_id' using errcode = '22023';
    end if;

    scope_department_id := (scope_item ->> 'department_id')::bigint;
    if scope_department_id <= 0 or not exists (select 1 from public.departments where id = scope_department_id) then
      raise exception 'scope department does not exist' using errcode = '23503';
    end if;

    if scope_item ? 'level_id' and jsonb_typeof(scope_item -> 'level_id') = 'number' then
      scope_level_id := (scope_item ->> 'level_id')::bigint;
      if scope_level_id <= 0 or not exists (select 1 from public.levels where id = scope_level_id) then
        raise exception 'scope level does not exist' using errcode = '23503';
      end if;
    elsif not (scope_item ? 'level_id') or jsonb_typeof(scope_item -> 'level_id') = 'null' then
      scope_level_id := null;
    else
      raise exception 'scope level_id must be numeric or null' using errcode = '22023';
    end if;
  end loop;

  delete from public.department_manager_scopes where profile_id = p_user_id;

  insert into public.department_manager_scopes(profile_id, department_id, level_id)
  select
    p_user_id,
    (item ->> 'department_id')::bigint,
    case when jsonb_typeof(item -> 'level_id') = 'number' then (item ->> 'level_id')::bigint else null end
  from jsonb_array_elements(p_scopes) as items(item);
end;
$$;

revoke all on function public.admin_set_department_manager_scopes(uuid, jsonb) from public, anon;
grant execute on function public.admin_set_department_manager_scopes(uuid, jsonb) to authenticated;

-- Wrap the existing profile admin RPC so profile + scope changes share one
-- transaction. The existing admin_update_profile() remains backwards compatible.
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

revoke all on function public.admin_update_profile_with_scopes(uuid, jsonb, jsonb) from public, anon;
grant execute on function public.admin_update_profile_with_scopes(uuid, jsonb, jsonb) to authenticated;

/* -------------------------------------------------------------------------- */
/* 3. Hall reservations                                                       */
/* -------------------------------------------------------------------------- */

create table if not exists public.hall_reservations (
  id bigint generated always as identity primary key,
  hall_id bigint not null references public.halls(id) on delete restrict,
  reservation_date date,
  day_of_week text,
  start_at time not null,
  end_at time not null,
  status text not null default 'active' check (status in ('active', 'canceled')),
  reason text,
  notes text,
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint hall_reservations_target_check check ((reservation_date is not null) <> (day_of_week is not null)),
  constraint hall_reservations_time_check check (start_at < end_at),
  constraint hall_reservations_reason_length_check check (reason is null or char_length(reason) <= 500),
  constraint hall_reservations_notes_length_check check (notes is null or char_length(notes) <= 2000)
);

create index if not exists hall_reservations_hall_status_idx
on public.hall_reservations(hall_id, status, reservation_date, day_of_week, start_at, end_at);

create index if not exists hall_reservations_created_by_idx
on public.hall_reservations(created_by, created_at desc);

grant select on public.hall_reservations to authenticated;
revoke insert, update, delete, truncate on public.hall_reservations from anon, authenticated;
alter table public.hall_reservations enable row level security;

drop policy if exists uhms_hall_reservations_select on public.hall_reservations;
create policy uhms_hall_reservations_select
on public.hall_reservations
for select to authenticated
using (public.is_active_user() and public.has_permission('hall_reservations.view'));

create or replace function public.uhms_date_matches_day(
  p_date date,
  p_day_of_week text
)
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

revoke all on function public.uhms_date_matches_day(date, text) from public, anon, authenticated;

create or replace function public.uhms_hall_reservation_matches_day(
  r public.hall_reservations,
  p_day_of_week text
)
returns boolean
security definer
set search_path = public, pg_temp
language sql
stable
as $$
  select (
    (r.reservation_date is null and r.day_of_week = p_day_of_week)
    or (r.reservation_date is not null and public.uhms_date_matches_day(r.reservation_date, p_day_of_week))
  );
$$;

revoke all on function public.uhms_hall_reservation_matches_day(public.hall_reservations, text) from public, anon, authenticated;

-- Returns conflict categories for a lecture slot. booking=true is a hard
-- unavailability flag; date-specific reservations conservatively block the
-- recurring lecture on that weekday because lectures have no date column.
create or replace function public.uhms_lecture_slot_conflict_types(
  p_hall_id bigint,
  p_day_of_week text,
  p_start_at time,
  p_end_at time,
  p_exclude_lecture_id bigint default null
)
returns text[]
security definer
set search_path = public, pg_temp
language plpgsql
stable
as $$
declare
  conflicts text[] := array[]::text[];
begin
  if exists (select 1 from public.halls where id = p_hall_id and booking = true) then
    conflicts := array_append(conflicts, 'hall_unavailable');
  end if;
  if exists (
    select 1 from public.hall_reservations r
    where r.hall_id = p_hall_id
      and r.status = 'active'
      and public.uhms_hall_reservation_matches_day(r, p_day_of_week)
      and p_start_at < r.end_at and p_end_at > r.start_at
  ) then
    conflicts := array_append(conflicts, 'reservation');
  end if;
  if exists (
    select 1 from public.lectures l
    where (p_exclude_lecture_id is null or l.id <> p_exclude_lecture_id)
      and l.canceled = false
      and l.day_of_week::text = p_day_of_week
      and l.hall_id = p_hall_id
      and p_start_at < l.end_at and p_end_at > l.start_at
  ) then
    conflicts := array_append(conflicts, 'hall');
  end if;
  return conflicts;
end;
$$;

revoke all on function public.uhms_lecture_slot_conflict_types(bigint, text, time, time, bigint) from public, anon, authenticated;

create or replace function public.uhms_reservation_conflict_exists(
  p_hall_id bigint,
  p_date date,
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
      and p_start_at < r.end_at and p_end_at > r.start_at
      and (
        (p_date is not null and r.reservation_date = p_date)
        or (p_date is not null and r.reservation_date is null and public.uhms_date_matches_day(p_date, r.day_of_week))
        or (p_date is null and r.reservation_date is not null and public.uhms_date_matches_day(r.reservation_date, p_day_of_week))
        or (p_date is null and r.reservation_date is null and r.day_of_week = p_day_of_week)
      )
  );
$$;

revoke all on function public.uhms_reservation_conflict_exists(bigint, date, text, time, time, bigint) from public, anon, authenticated;

create or replace function public.find_hall_reservation_conflicts(
  p_hall_id bigint,
  p_reservation_date date,
  p_day_of_week text,
  p_start_at time,
  p_end_at time,
  p_exclude_id bigint default null
)
returns table (
  conflict_type text,
  conflict_id bigint,
  conflict_start time,
  conflict_end time
)
security definer
set search_path = public, pg_temp
language plpgsql
stable
as $$
declare
  required_permission text;
begin
  if auth.uid() is null or not public.is_active_user() then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  required_permission := case when p_exclude_id is null then 'hall_reservations.create' else 'hall_reservations.update' end;
  if not public.has_permission(required_permission) then
    raise exception 'the current user cannot manage hall reservations' using errcode = '42501';
  end if;
  if p_hall_id is null or not exists (select 1 from public.halls where id = p_hall_id) then
    raise exception 'hall does not exist' using errcode = '23503';
  end if;
  if (p_reservation_date is null) = (p_day_of_week is null or btrim(p_day_of_week) = '') then
    raise exception 'provide either reservation_date or day_of_week, but not both' using errcode = '22023';
  end if;
  if p_day_of_week is not null and not public.uhms_enum_value_exists('public.lectures'::regclass, 'day_of_week', p_day_of_week) then
    raise exception 'day_of_week is not a valid value' using errcode = '22023';
  end if;
  if p_start_at is null or p_end_at is null or p_start_at >= p_end_at then
    raise exception 'start_at must be earlier than end_at' using errcode = '22023';
  end if;

  return query
    select 'reservation'::text, r.id, r.start_at, r.end_at
    from public.hall_reservations r
    where r.id is distinct from p_exclude_id
      and r.hall_id = p_hall_id and r.status = 'active'
      and p_start_at < r.end_at and p_end_at > r.start_at
      and (
        (p_reservation_date is not null and r.reservation_date = p_reservation_date)
        or (p_reservation_date is not null and r.reservation_date is null and public.uhms_date_matches_day(p_reservation_date, r.day_of_week))
        or (p_reservation_date is null and r.reservation_date is not null and public.uhms_date_matches_day(r.reservation_date, p_day_of_week))
        or (p_reservation_date is null and r.reservation_date is null and r.day_of_week = p_day_of_week)
      )
    union all
    select 'lecture'::text, l.id, l.start_at, l.end_at
    from public.lectures l
    where l.canceled = false
      and l.hall_id = p_hall_id
      and p_start_at < l.end_at and p_end_at > l.start_at
      and (
        (p_reservation_date is not null and public.uhms_date_matches_day(p_reservation_date, l.day_of_week::text))
        or (p_reservation_date is null and l.day_of_week::text = p_day_of_week)
      );
end;
$$;

grant execute on function public.find_hall_reservation_conflicts(bigint, date, text, time, time, bigint) to authenticated;
revoke execute on function public.find_hall_reservation_conflicts(bigint, date, text, time, time, bigint) from public, anon;

create or replace function public.save_hall_reservation(
  p_reservation_id bigint,
  p_payload jsonb
)
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
  reservation_conflict boolean;
  lecture_conflict boolean;
begin
  if auth.uid() is null or not public.is_active_user() then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'reservation payload must be a JSON object' using errcode = '22023';
  end if;
  required_permission := case when p_reservation_id is null then 'hall_reservations.create' else 'hall_reservations.update' end;
  if not public.has_permission(required_permission) then
    raise exception 'the current user cannot manage hall reservations' using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(918273645::bigint);
  if p_reservation_id is not null then
    select * into current_reservation from public.hall_reservations where id = p_reservation_id for update;
    if current_reservation.id is null then
      raise exception 'reservation was not found' using errcode = 'P0002';
    end if;
  end if;

  if (p_payload ->> 'hall_id') !~ '^[1-9][0-9]*$' then
    raise exception 'hall_id must be a positive integer' using errcode = '22023';
  end if;
  hall_value := (p_payload ->> 'hall_id')::bigint;
  if not exists (select 1 from public.halls where id = hall_value) then
    raise exception 'hall does not exist' using errcode = '23503';
  end if;

  if p_payload ? 'reservation_date' and jsonb_typeof(p_payload -> 'reservation_date') = 'string' then
    reservation_date_value := (p_payload ->> 'reservation_date')::date;
  else
    reservation_date_value := null;
  end if;
  day_value := nullif(btrim(p_payload ->> 'day_of_week'), '');
  if (reservation_date_value is null) = (day_value is null) then
    raise exception 'provide either reservation_date or day_of_week, but not both' using errcode = '22023';
  end if;
  if day_value is not null and not public.uhms_enum_value_exists('public.lectures'::regclass, 'day_of_week', day_value) then
    raise exception 'day_of_week is not a valid value' using errcode = '22023';
  end if;
  begin
    start_value := (p_payload ->> 'start_at')::time;
    end_value := (p_payload ->> 'end_at')::time;
  exception when others then
    raise exception 'start_at and end_at must be valid times' using errcode = '22023';
  end;
  if start_value is null or end_value is null or start_value >= end_value then
    raise exception 'start_at must be earlier than end_at' using errcode = '22023';
  end if;
  reason_value := nullif(btrim(p_payload ->> 'reason'), '');
  notes_value := nullif(btrim(p_payload ->> 'notes'), '');
  if char_length(reason_value) > 500 or char_length(notes_value) > 2000 then
    raise exception 'reason or notes is too long' using errcode = '22023';
  end if;

  if exists (select 1 from public.halls where id = hall_value and booking = true) then
    raise exception 'لا يمكن حجز القاعة لأنها غير متاحة إداريًا' using errcode = 'P0001';
  end if;
  reservation_conflict := public.uhms_reservation_conflict_exists(hall_value, reservation_date_value, day_value, start_value, end_value, p_reservation_id);
  if reservation_conflict then
    raise exception 'لا يمكن حفظ الحجز: يوجد حجز آخر متداخل للقاعة' using errcode = 'P0001';
  end if;
  lecture_conflict := exists (
    select 1 from public.lectures l
    where l.canceled = false and l.hall_id = hall_value
      and start_value < l.end_at and end_value > l.start_at
      and ((reservation_date_value is not null and public.uhms_date_matches_day(reservation_date_value, l.day_of_week::text)) or (reservation_date_value is null and l.day_of_week::text = day_value))
  );
  if lecture_conflict then
    raise exception 'لا يمكن حفظ الحجز: يتعارض مع محاضرة مجدولة' using errcode = 'P0001';
  end if;

  if p_reservation_id is null then
    insert into public.hall_reservations(hall_id, reservation_date, day_of_week, start_at, end_at, status, reason, notes, created_by, updated_by)
    values (hall_value, reservation_date_value, day_value, start_value, end_value, 'active', reason_value, notes_value, auth.uid(), auth.uid())
    returning * into saved_reservation;
  else
    update public.hall_reservations
    set hall_id = hall_value, reservation_date = reservation_date_value, day_of_week = day_value,
        start_at = start_value, end_at = end_value, reason = reason_value, notes = notes_value,
        updated_by = auth.uid(), updated_at = now()
    where id = p_reservation_id
    returning * into saved_reservation;
  end if;
  return saved_reservation;
end;
$$;

grant execute on function public.save_hall_reservation(bigint, jsonb) to authenticated;
revoke execute on function public.save_hall_reservation(bigint, jsonb) from public, anon;

create or replace function public.set_hall_reservation_status(
  p_reservation_id bigint,
  p_status text,
  p_reason text default null
)
returns public.hall_reservations
security definer
set search_path = public, pg_temp
language plpgsql
as $$
declare
  target_reservation public.hall_reservations;
  updated_reservation public.hall_reservations;
  conflict_types text[];
  clean_reason text := nullif(btrim(coalesce(p_reason, '')), '');
  lecture_conflict boolean;
begin
  if auth.uid() is null or not public.is_active_user() then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if not public.has_permission('hall_reservations.cancel') then
    raise exception 'the current user cannot change reservation status' using errcode = '42501';
  end if;
  if p_reservation_id is null or p_reservation_id <= 0 or p_status not in ('active', 'canceled') then
    raise exception 'reservation id or status is invalid' using errcode = '22023';
  end if;
  if clean_reason is not null and char_length(clean_reason) > 500 then
    raise exception 'reason must not exceed 500 characters' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(918273645::bigint);
  select * into target_reservation from public.hall_reservations where id = p_reservation_id for update;
  if target_reservation.id is null then
    raise exception 'reservation was not found' using errcode = 'P0002';
  end if;
  if target_reservation.status = p_status then
    return target_reservation;
  end if;

  if p_status = 'active' then
    if exists (select 1 from public.halls where id = target_reservation.hall_id and booking = true) then
      raise exception 'لا يمكن تفعيل الحجز لأن القاعة غير متاحة إداريًا' using errcode = 'P0001';
    end if;
    if public.uhms_reservation_conflict_exists(target_reservation.hall_id, target_reservation.reservation_date, target_reservation.day_of_week, target_reservation.start_at, target_reservation.end_at, target_reservation.id) then
      raise exception 'لا يمكن تفعيل الحجز: يوجد حجز آخر متداخل' using errcode = 'P0001';
    end if;
    lecture_conflict := exists (
      select 1 from public.lectures l
      where l.canceled = false and l.hall_id = target_reservation.hall_id
        and target_reservation.start_at < l.end_at and target_reservation.end_at > l.start_at
        and ((target_reservation.reservation_date is not null and public.uhms_date_matches_day(target_reservation.reservation_date, l.day_of_week::text)) or (target_reservation.reservation_date is null and l.day_of_week::text = target_reservation.day_of_week))
    );
    if lecture_conflict then
      raise exception 'لا يمكن تفعيل الحجز: يتعارض مع محاضرة مجدولة' using errcode = 'P0001';
    end if;
  end if;

  update public.hall_reservations
  set status = p_status, reason = coalesce(clean_reason, reason), updated_by = auth.uid(), updated_at = now()
  where id = target_reservation.id
  returning * into updated_reservation;
  return updated_reservation;
end;
$$;

grant execute on function public.set_hall_reservation_status(bigint, text, text) to authenticated;
revoke execute on function public.set_hall_reservation_status(bigint, text, text) from public, anon;

/* -------------------------------------------------------------------------- */
/* 4. Scope-aware academic policies                                            */
/* -------------------------------------------------------------------------- */

-- Replace only policies created by this project. Anonymous/public policies,
-- if used by Flutter, are not touched.
drop policy if exists departments_view on public.departments;
drop policy if exists departments_create on public.departments;
drop policy if exists departments_update on public.departments;
drop policy if exists departments_delete on public.departments;
drop policy if exists uhms_departments_select on public.departments;
drop policy if exists uhms_departments_insert on public.departments;
drop policy if exists uhms_departments_update on public.departments;
drop policy if exists uhms_departments_delete on public.departments;
drop policy if exists uhms_academic_departments_select on public.departments;
drop policy if exists uhms_academic_departments_insert on public.departments;
drop policy if exists uhms_academic_departments_update on public.departments;
drop policy if exists uhms_academic_departments_delete on public.departments;

create policy uhms_scoped_departments_select on public.departments
for select to authenticated
using (public.has_permission('departments.view') and public.department_manager_scope_allowed(id, null));
create policy uhms_scoped_departments_insert on public.departments
for insert to authenticated
with check (public.has_permission('departments.create'));
create policy uhms_scoped_departments_update on public.departments
for update to authenticated
using (public.has_permission('departments.update') and public.department_manager_scope_allowed(id, null))
with check (public.has_permission('departments.update') and public.department_manager_scope_allowed(id, null));
create policy uhms_scoped_departments_delete on public.departments
for delete to authenticated
using (public.has_permission('departments.delete'));

drop policy if exists batches_view on public.batches;
drop policy if exists batches_create on public.batches;
drop policy if exists batches_update on public.batches;
drop policy if exists batches_delete on public.batches;
drop policy if exists uhms_batches_select on public.batches;
drop policy if exists uhms_batches_insert on public.batches;
drop policy if exists uhms_batches_update on public.batches;
drop policy if exists uhms_batches_delete on public.batches;
drop policy if exists uhms_academic_batches_select on public.batches;
drop policy if exists uhms_academic_batches_insert on public.batches;
drop policy if exists uhms_academic_batches_update on public.batches;
drop policy if exists uhms_academic_batches_delete on public.batches;

create policy uhms_scoped_batches_select on public.batches
for select to authenticated
using (public.has_permission('batches.view') and public.department_manager_scope_allowed(department_id, level_id));
create policy uhms_scoped_batches_insert on public.batches
for insert to authenticated
with check (public.has_permission('batches.create') and public.department_manager_scope_allowed(department_id, level_id));
create policy uhms_scoped_batches_update on public.batches
for update to authenticated
using (public.has_permission('batches.update') and public.department_manager_scope_allowed(department_id, level_id))
with check (public.has_permission('batches.update') and public.department_manager_scope_allowed(department_id, level_id));
create policy uhms_scoped_batches_delete on public.batches
for delete to authenticated
using (public.has_permission('batches.delete') and public.department_manager_scope_allowed(department_id, level_id));

drop policy if exists levels_view on public.levels;
drop policy if exists levels_create on public.levels;
drop policy if exists levels_update on public.levels;
drop policy if exists levels_delete on public.levels;
drop policy if exists uhms_levels_select on public.levels;
drop policy if exists uhms_levels_insert on public.levels;
drop policy if exists uhms_levels_update on public.levels;
drop policy if exists uhms_levels_delete on public.levels;
drop policy if exists uhms_academic_levels_select on public.levels;
drop policy if exists uhms_academic_levels_insert on public.levels;
drop policy if exists uhms_academic_levels_update on public.levels;
drop policy if exists uhms_academic_levels_delete on public.levels;

create policy uhms_scoped_levels_select on public.levels
for select to authenticated
using (public.has_permission('levels.view') and public.department_manager_level_allowed(id));
create policy uhms_scoped_levels_insert on public.levels
for insert to authenticated
with check (public.has_permission('levels.create'));
create policy uhms_scoped_levels_update on public.levels
for update to authenticated
using (public.has_permission('levels.update'))
with check (public.has_permission('levels.update'));
create policy uhms_scoped_levels_delete on public.levels
for delete to authenticated
using (public.has_permission('levels.delete'));

drop policy if exists lectures_view on public.lectures;
drop policy if exists lectures_create on public.lectures;
drop policy if exists lectures_update on public.lectures;
drop policy if exists lectures_cancel on public.lectures;
drop policy if exists uhms_academic_lectures_select on public.lectures;
drop policy if exists uhms_academic_lectures_insert on public.lectures;
drop policy if exists uhms_academic_lectures_update on public.lectures;
drop policy if exists uhms_academic_lectures_cancel on public.lectures;

create policy uhms_scoped_lectures_select on public.lectures
for select to authenticated
using (
  public.has_permission('lectures.view')
  and exists (select 1 from public.batches b where b.id = lectures.batch_id and public.department_manager_scope_allowed(b.department_id, b.level_id))
);
create policy uhms_scoped_lectures_insert on public.lectures
for insert to authenticated
with check (
  public.has_permission('lectures.create')
  and exists (select 1 from public.batches b where b.id = batch_id and public.department_manager_scope_allowed(b.department_id, b.level_id))
);
create policy uhms_scoped_lectures_update on public.lectures
for update to authenticated
using (
  public.has_permission('lectures.update')
  and exists (select 1 from public.batches b where b.id = lectures.batch_id and public.department_manager_scope_allowed(b.department_id, b.level_id))
)
with check (
  public.has_permission('lectures.update')
  and exists (select 1 from public.batches b where b.id = batch_id and public.department_manager_scope_allowed(b.department_id, b.level_id))
);
create policy uhms_scoped_lectures_cancel on public.lectures
for update to authenticated
using (
  public.has_permission('lectures.cancel')
  and exists (select 1 from public.batches b where b.id = lectures.batch_id and public.department_manager_scope_allowed(b.department_id, b.level_id))
)
with check (
  public.has_permission('lectures.cancel')
  and exists (select 1 from public.batches b where b.id = batch_id and public.department_manager_scope_allowed(b.department_id, b.level_id))
);

/* -------------------------------------------------------------------------- */
/* 5. Useful indexes for scoped reads                                          */
/* -------------------------------------------------------------------------- */

create index if not exists batches_department_level_idx on public.batches(department_id, level_id);
create index if not exists lectures_batch_day_time_idx on public.lectures(batch_id, day_of_week, start_at, end_at) where canceled = false;
