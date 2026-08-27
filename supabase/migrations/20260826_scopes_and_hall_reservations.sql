-- University Hall Management System: Department Manager scopes and WEEKLY hall reservations.
-- Incremental migration for an existing installation.
-- It does not drop/truncate/delete data or alter existing academic columns.
-- It intentionally does not implement reservation_date yet: lectures are recurring
-- by day_of_week, so date-specific reservations require a later occurrence model.
-- Run after schema.sql, functions.sql, policies.sql and schedule_hardening.sql.

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
/* 2. Department/level relationship and Department Manager scopes             */
/* -------------------------------------------------------------------------- */

-- Levels are global reference rows in the legacy schema. This additive mapping
-- makes the department/level relationship explicit without changing Flutter's
-- existing levels table.
create table if not exists public.department_levels (
  department_id bigint not null references public.departments(id) on delete cascade,
  level_id bigint not null references public.levels(id) on delete restrict,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  primary key (department_id, level_id)
);

create index if not exists department_levels_level_idx
on public.department_levels(level_id, department_id);

-- Backfill only relationships that are already evidenced by existing batches.
insert into public.department_levels(department_id, level_id, is_active)
select distinct b.department_id, b.level_id, true
from public.batches b
where b.level_id is not null
on conflict (department_id, level_id) do update set is_active = true;

grant select on public.department_levels to authenticated;
revoke insert, update, delete, truncate on public.department_levels from anon, authenticated;
alter table public.department_levels enable row level security;

drop policy if exists uhms_department_levels_select on public.department_levels;
create policy uhms_department_levels_select
on public.department_levels
for select to authenticated
using (public.is_active_user());

-- Optional administrative mapping API. It never removes a mapping that is used
-- by an existing batch; deactivate unused mappings instead.
create or replace function public.admin_set_department_levels(
  p_department_id bigint,
  p_level_ids jsonb
)
returns void
security definer
set search_path = public, pg_temp
language plpgsql
as $$
declare
  level_item jsonb;
  level_value bigint;
begin
  if auth.uid() is null or not public.is_active_user() or not public.has_permission('departments.update') then
    raise exception 'the current user cannot manage department levels' using errcode = '42501';
  end if;
  if p_department_id is null or not exists (select 1 from public.departments where id = p_department_id) then
    raise exception 'department does not exist' using errcode = '23503';
  end if;
  if p_level_ids is null or jsonb_typeof(p_level_ids) <> 'array' then
    raise exception 'p_level_ids must be a JSON array' using errcode = '22023';
  end if;

  for level_item in select value from jsonb_array_elements(p_level_ids)
  loop
    if jsonb_typeof(level_item) <> 'number' then
      raise exception 'level ids must be positive integers' using errcode = '22023';
    end if;
    level_value := (level_item #>> '{}')::bigint;
    if level_value <= 0 or not exists (select 1 from public.levels where id = level_value) then
      raise exception 'level does not exist' using errcode = '23503';
    end if;
  end loop;

  update public.department_levels dl
  set is_active = false
  where dl.department_id = p_department_id
    and not exists (
      select 1 from jsonb_array_elements(p_level_ids) items(value)
      where (items.value #>> '{}')::bigint = dl.level_id
    )
    and not exists (select 1 from public.batches b where b.department_id = dl.department_id and b.level_id = dl.level_id);

  insert into public.department_levels(department_id, level_id, is_active)
  select p_department_id, (items.value #>> '{}')::bigint, true
  from jsonb_array_elements(p_level_ids) items(value)
  on conflict (department_id, level_id) do update set is_active = true;
end;
$$;

revoke all on function public.admin_set_department_levels(bigint, jsonb) from public, anon;
grant execute on function public.admin_set_department_levels(bigint, jsonb) to authenticated;

create or replace function public.uhms_sync_department_level_from_batch()
returns trigger
security definer
set search_path = public, pg_temp
language plpgsql
as $$
begin
  if new.level_id is not null then
    insert into public.department_levels(department_id, level_id, is_active)
    values (new.department_id, new.level_id, true)
    on conflict (department_id, level_id) do update set is_active = true;
  end if;
  return new;
end;
$$;

revoke all on function public.uhms_sync_department_level_from_batch() from public, anon, authenticated;

do $$
begin
  if not exists (
    select 1 from pg_trigger
    where tgname = 'uhms_sync_department_level_from_batch'
      and tgrelid = 'public.batches'::regclass
      and not tgisinternal
  ) then
    execute 'create trigger uhms_sync_department_level_from_batch before insert or update on public.batches for each row execute function public.uhms_sync_department_level_from_batch()';
  end if;
end;
$$;

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
  select exists (select 1 from public.department_manager_scopes s where s.profile_id = auth.uid()) into has_explicit_scopes;
  if not has_explicit_scopes then
    return p_department_id = public.current_department_id();
  end if;
  return exists (
    select 1 from public.department_manager_scopes s
    where s.profile_id = auth.uid()
      and s.department_id = p_department_id
      and (p_level_id is null or s.level_id is null or s.level_id = p_level_id)
      and (
        p_level_id is null
        or exists (
          select 1 from public.department_levels dl
          where dl.department_id = p_department_id
            and dl.level_id = p_level_id
            and dl.is_active = true
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
declare
  has_explicit_scopes boolean;
begin
  if auth.uid() is null or not public.is_active_user() then return false; end if;
  if public.current_role_key() <> 'department_manager' then return true; end if;
  select exists (select 1 from public.department_manager_scopes s where s.profile_id = auth.uid()) into has_explicit_scopes;
  if not has_explicit_scopes then return true; end if;
  return exists (
    select 1
    from public.department_manager_scopes s
    join public.department_levels dl
      on dl.department_id = s.department_id
     and dl.level_id = p_level_id
     and dl.is_active = true
    where s.profile_id = auth.uid()
      and (s.level_id is null or s.level_id = p_level_id)
  );
end;
$$;

revoke all on function public.department_manager_scope_allowed(bigint, bigint) from public, anon;
revoke all on function public.department_manager_level_allowed(bigint) from public, anon;
grant execute on function public.department_manager_scope_allowed(bigint, bigint) to authenticated;
grant execute on function public.department_manager_level_allowed(bigint) to authenticated;

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
begin
  if auth.uid() is null then raise exception 'not authenticated' using errcode = '28000'; end if;
  if not public.is_active_user() or not public.is_super_admin() then raise exception 'only an active super_admin may manage department scopes' using errcode = '42501'; end if;
  if p_user_id is null or p_scopes is null or jsonb_typeof(p_scopes) <> 'array' then raise exception 'p_user_id and a JSON array of scopes are required' using errcode = '22023'; end if;
  select * into target_profile from public.profiles where id = p_user_id;
  if target_profile.id is null then raise exception 'profile was not found' using errcode = 'P0002'; end if;
  if target_profile.role <> 'department_manager' and jsonb_array_length(p_scopes) > 0 then raise exception 'scopes can only be assigned to a department_manager' using errcode = '22023'; end if;
  for scope_item in select value from jsonb_array_elements(p_scopes)
  loop
    if jsonb_typeof(scope_item) <> 'object' or not (scope_item ? 'department_id') or jsonb_typeof(scope_item -> 'department_id') <> 'number' then
      raise exception 'each scope needs a numeric department_id' using errcode = '22023';
    end if;
    scope_department_id := (scope_item ->> 'department_id')::bigint;
    if scope_department_id <= 0 or not exists (select 1 from public.departments where id = scope_department_id) then raise exception 'scope department does not exist' using errcode = '23503'; end if;
    if scope_item ? 'level_id' and jsonb_typeof(scope_item -> 'level_id') = 'number' then
      scope_level_id := (scope_item ->> 'level_id')::bigint;
      if scope_level_id <= 0 or not exists (select 1 from public.levels where id = scope_level_id) then raise exception 'scope level does not exist' using errcode = '23503'; end if;
      if not exists (select 1 from public.department_levels dl where dl.department_id = scope_department_id and dl.level_id = scope_level_id and dl.is_active = true) then raise exception 'scope level is not assigned to the selected department' using errcode = '42501'; end if;
    elsif not (scope_item ? 'level_id') or jsonb_typeof(scope_item -> 'level_id') = 'null' then
      scope_level_id := null;
    else
      raise exception 'scope level_id must be numeric or null' using errcode = '22023';
    end if;
  end loop;
  delete from public.department_manager_scopes where profile_id = p_user_id;
  insert into public.department_manager_scopes(profile_id, department_id, level_id)
  select p_user_id, (item ->> 'department_id')::bigint,
         case when jsonb_typeof(item -> 'level_id') = 'number' then (item ->> 'level_id')::bigint else null end
  from jsonb_array_elements(p_scopes) as items(item);
end;
$$;

revoke all on function public.admin_set_department_manager_scopes(uuid, jsonb) from public, anon;
grant execute on function public.admin_set_department_manager_scopes(uuid, jsonb) to authenticated;

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
declare updated_profile public.profiles;
begin
  updated_profile := public.admin_update_profile(p_user_id, p_patch);
  perform public.admin_set_department_manager_scopes(p_user_id, coalesce(p_scopes, '[]'::jsonb));
  return updated_profile;
end;
$$;

revoke all on function public.admin_update_profile_with_scopes(uuid, jsonb, jsonb) from public, anon;
grant execute on function public.admin_update_profile_with_scopes(uuid, jsonb, jsonb) to authenticated;

/* -------------------------------------------------------------------------- */
/* 3. Weekly hall reservations only                                           */
/* -------------------------------------------------------------------------- */

create table if not exists public.hall_reservations (
  id bigint generated always as identity primary key,
  hall_id bigint not null references public.halls(id) on delete restrict,
  day_of_week text not null,
  start_at time not null,
  end_at time not null,
  status text not null default 'active' check (status in ('active', 'canceled')),
  reason text,
  notes text,
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint hall_reservations_time_check check (start_at < end_at),
  constraint hall_reservations_reason_length_check check (reason is null or char_length(reason) <= 500),
  constraint hall_reservations_notes_length_check check (notes is null or char_length(notes) <= 2000)
);

create index if not exists hall_reservations_hall_day_status_idx
on public.hall_reservations(hall_id, day_of_week, status, start_at, end_at);

grant select on public.hall_reservations to authenticated;
revoke insert, update, delete, truncate on public.hall_reservations from anon, authenticated;
alter table public.hall_reservations enable row level security;

drop policy if exists uhms_hall_reservations_select on public.hall_reservations;
create policy uhms_hall_reservations_select
on public.hall_reservations
for select to authenticated
using (public.is_active_user() and public.has_permission('hall_reservations.view'));

create or replace function public.uhms_weekly_reservation_conflict_exists(
  p_hall_id bigint,
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
    select 1 from public.hall_reservations r
    where r.id is distinct from p_exclude_id
      and r.hall_id = p_hall_id
      and r.day_of_week = p_day_of_week
      and r.status = 'active'
      and p_start_at < r.end_at
      and p_end_at > r.start_at
  );
$$;

revoke all on function public.uhms_weekly_reservation_conflict_exists(bigint, text, time, time, bigint) from public, anon, authenticated;

create or replace function public.find_hall_reservation_conflicts(
  p_hall_id bigint,
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
  if not public.uhms_enum_value_exists('public.lectures'::regclass, 'day_of_week', p_day_of_week) then raise exception 'day_of_week is not a valid value' using errcode = '22023'; end if;
  if p_start_at is null or p_end_at is null or p_start_at >= p_end_at then raise exception 'start_at must be earlier than end_at' using errcode = '22023'; end if;
  return query
    select 'reservation'::text, r.id, r.start_at, r.end_at
    from public.hall_reservations r
    where r.id is distinct from p_exclude_id and r.hall_id = p_hall_id and r.day_of_week = p_day_of_week and r.status = 'active'
      and p_start_at < r.end_at and p_end_at > r.start_at
    union all
    select 'lecture'::text, l.id, l.start_at, l.end_at
    from public.lectures l
    where l.canceled = false and l.hall_id = p_hall_id and l.day_of_week::text = p_day_of_week
      and p_start_at < l.end_at and p_end_at > l.start_at;
end;
$$;

grant execute on function public.find_hall_reservation_conflicts(bigint, text, time, time, bigint) to authenticated;
revoke execute on function public.find_hall_reservation_conflicts(bigint, text, time, time, bigint) from public, anon;

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
  day_value := nullif(btrim(p_payload ->> 'day_of_week'), '');
  if day_value is null or not public.uhms_enum_value_exists('public.lectures'::regclass, 'day_of_week', day_value) then raise exception 'day_of_week is not a valid value' using errcode = '22023'; end if;
  begin
    start_value := (p_payload ->> 'start_at')::time;
    end_value := (p_payload ->> 'end_at')::time;
  exception when others then
    raise exception 'start_at and end_at must be valid times' using errcode = '22023';
  end;
  if start_value is null or end_value is null or start_value >= end_value then raise exception 'start_at must be earlier than end_at' using errcode = '22023'; end if;
  reason_value := nullif(btrim(p_payload ->> 'reason'), '');
  notes_value := nullif(btrim(p_payload ->> 'notes'), '');
  if char_length(reason_value) > 500 or char_length(notes_value) > 2000 then raise exception 'reason or notes is too long' using errcode = '22023'; end if;
  if exists (select 1 from public.halls where id = hall_value and booking = true) then raise exception 'لا يمكن حجز القاعة لأنها غير متاحة إداريًا' using errcode = 'P0001'; end if;
  if public.uhms_weekly_reservation_conflict_exists(hall_value, day_value, start_value, end_value, p_reservation_id) then raise exception 'لا يمكن حفظ الحجز: يوجد حجز آخر متداخل للقاعة' using errcode = 'P0001'; end if;
  if exists (select 1 from public.lectures l where l.canceled = false and l.hall_id = hall_value and l.day_of_week::text = day_value and start_value < l.end_at and end_value > l.start_at) then raise exception 'لا يمكن حفظ الحجز: يتعارض مع محاضرة مجدولة' using errcode = 'P0001'; end if;
  if p_reservation_id is null then
    insert into public.hall_reservations(hall_id, day_of_week, start_at, end_at, status, reason, notes, created_by, updated_by)
    values (hall_value, day_value, start_value, end_value, 'active', reason_value, notes_value, auth.uid(), auth.uid()) returning * into saved_reservation;
  else
    update public.hall_reservations
    set hall_id = hall_value, day_of_week = day_value, start_at = start_value, end_at = end_value,
        reason = reason_value, notes = notes_value, updated_by = auth.uid(), updated_at = now()
    where id = p_reservation_id returning * into saved_reservation;
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
begin
  if auth.uid() is null or not public.is_active_user() then raise exception 'not authenticated' using errcode = '28000'; end if;
  if not public.has_permission('hall_reservations.cancel') then raise exception 'the current user cannot change reservation status' using errcode = '42501'; end if;
  if p_reservation_id is null or p_reservation_id <= 0 or p_status not in ('active', 'canceled') then raise exception 'reservation id or status is invalid' using errcode = '22023'; end if;
  if clean_reason is not null and char_length(clean_reason) > 500 then raise exception 'reason must not exceed 500 characters' using errcode = '22023'; end if;
  perform pg_advisory_xact_lock(918273645::bigint);
  select * into target_reservation from public.hall_reservations where id = p_reservation_id for update;
  if target_reservation.id is null then raise exception 'reservation was not found' using errcode = 'P0002'; end if;
  if target_reservation.status = p_status then return target_reservation; end if;
  if p_status = 'active' then
    if exists (select 1 from public.halls where id = target_reservation.hall_id and booking = true) then raise exception 'لا يمكن تفعيل الحجز لأن القاعة غير متاحة إداريًا' using errcode = 'P0001'; end if;
    if public.uhms_weekly_reservation_conflict_exists(target_reservation.hall_id, target_reservation.day_of_week, target_reservation.start_at, target_reservation.end_at, target_reservation.id) then raise exception 'لا يمكن تفعيل الحجز: يوجد حجز آخر متداخل' using errcode = 'P0001'; end if;
    if exists (select 1 from public.lectures l where l.canceled = false and l.hall_id = target_reservation.hall_id and l.day_of_week::text = target_reservation.day_of_week and target_reservation.start_at < l.end_at and target_reservation.end_at > l.start_at) then raise exception 'لا يمكن تفعيل الحجز: يتعارض مع محاضرة مجدولة' using errcode = 'P0001'; end if;
  end if;
  update public.hall_reservations set status = p_status, reason = coalesce(clean_reason, reason), updated_by = auth.uid(), updated_at = now() where id = target_reservation.id returning * into updated_reservation;
  return updated_reservation;
end;
$$;

grant execute on function public.set_hall_reservation_status(bigint, text, text) to authenticated;
revoke execute on function public.set_hall_reservation_status(bigint, text, text) from public, anon;

/* -------------------------------------------------------------------------- */
/* 4. Scope-aware RLS without trusting policy names                            */
/* -------------------------------------------------------------------------- */

-- These are RESTRICTIVE policies. They combine with any existing permissive
-- policy, so an old policy cannot bypass the new Department Manager scope.
-- No existing policy is dropped; this protects Flutter/custom policies.

drop policy if exists uhms_scope_departments_restrictive on public.departments;
create policy uhms_scope_departments_restrictive on public.departments as restrictive
for all to authenticated
using (not public.is_department_manager() or public.department_manager_scope_allowed(id, null))
with check (not public.is_department_manager() or public.department_manager_scope_allowed(id, null));

drop policy if exists uhms_scope_batches_restrictive on public.batches;
create policy uhms_scope_batches_restrictive on public.batches as restrictive
for all to authenticated
using (not public.is_department_manager() or public.department_manager_scope_allowed(department_id, level_id))
with check (not public.is_department_manager() or public.department_manager_scope_allowed(department_id, level_id));

drop policy if exists uhms_department_level_relationship_restrictive on public.batches;
create policy uhms_department_level_relationship_restrictive on public.batches as restrictive
for all to authenticated
using (level_id is null or exists (select 1 from public.department_levels dl where dl.department_id = batches.department_id and dl.level_id = batches.level_id and dl.is_active = true))
with check (level_id is null or exists (select 1 from public.department_levels dl where dl.department_id = batches.department_id and dl.level_id = batches.level_id and dl.is_active = true));

drop policy if exists uhms_scope_levels_restrictive on public.levels;
create policy uhms_scope_levels_restrictive on public.levels as restrictive
for all to authenticated
using (not public.is_department_manager() or public.department_manager_level_allowed(id))
with check (not public.is_department_manager() or public.department_manager_level_allowed(id));

drop policy if exists uhms_scope_lectures_restrictive on public.lectures;
create policy uhms_scope_lectures_restrictive on public.lectures as restrictive
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

/* -------------------------------------------------------------------------- */
/* 5. Schedule RPC/trigger overrides                                           */
/* -------------------------------------------------------------------------- */

-- The definitions below are appended programmatically from the canonical
-- schedule hardening functions and add booking/reservation checks. They use
-- the scope helper above for Department Manager validation.

/* SCHEDULE_SCOPE_RESERVATION_RPC_OVERRIDES */
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

  if exists (select 1 from public.halls where id = new.hall_id and booking = true) then
    raise exception 'لا يمكن حفظ المحاضرة: القاعة غير متاحة للجدولة' using errcode = 'P0001';
  end if;
  if exists (
    select 1 from public.hall_reservations r
    where r.hall_id = new.hall_id
      and r.status = 'active'
      and r.day_of_week = new.day_of_week::text
      and new.start_at < r.end_at
      and new.end_at > r.start_at
  ) then
    raise exception 'لا يمكن حفظ المحاضرة: القاعة محجوزة في هذا الوقت' using errcode = 'P0001';
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
  if exists (select 1 from public.halls where id = hall_value and booking = true) then
    raise exception 'لا يمكن حفظ المحاضرة: القاعة غير متاحة للجدولة' using errcode = 'P0001';
  end if;
  if exists (
    select 1 from public.hall_reservations r
    where r.hall_id = hall_value
      and r.status = 'active'
      and r.day_of_week = day_value
      and start_value < r.end_at
      and end_value > r.start_at
  ) then
    raise exception 'لا يمكن حفظ المحاضرة: القاعة محجوزة في هذا الوقت' using errcode = 'P0001';
  end if;
  if not exists (select 1 from public.instructors where id = instructor_value) then
    raise exception 'instructor_id does not reference an existing instructor' using errcode = '23503';
  end if;
  if not exists (select 1 from public.batches where id = batch_value) then
    raise exception 'batch_id does not reference an existing batch' using errcode = '23503';
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
      and r.day_of_week = target_lecture.day_of_week::text
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

