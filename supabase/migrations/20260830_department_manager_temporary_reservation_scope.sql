-- Phase 1 incremental repair: allow Department Managers to manage only
-- temporary hall reservations belonging to their active department/level Scope.
--
-- Run this file after:
--   20260827_phase1_scope_occurrence_reservations.sql
--
-- This migration reuses hall_reservations and the existing permission keys.
-- It adds only nullable scope columns to the reused reservation table and does
-- not modify or delete academic rows. Department Managers remain unable to
-- cancel a recurring lecture series.

/* -------------------------------------------------------------------------- */
/* 0. Fail-closed prerequisite check                                           */
/* -------------------------------------------------------------------------- */

do $$
declare
  required_column text;
begin
  if to_regclass('public.hall_reservations') is null
     or to_regclass('public.department_levels') is null
     or to_regclass('public.department_manager_scopes') is null then
    raise exception 'Phase 1 base tables are missing; run 20260827_phase1_scope_occurrence_reservations.sql first'
      using errcode = '42P01';
  end if;

  foreach required_column in array array[
    'id', 'hall_id', 'reservation_date', 'day_of_week', 'start_at', 'end_at',
    'status', 'reason', 'notes', 'created_by', 'updated_by', 'created_at', 'updated_at'
  ] loop
    if not exists (
      select 1
      from pg_attribute
      where attrelid = 'public.hall_reservations'::regclass
        and attname = required_column
        and attnum > 0
        and not attisdropped
    ) then
      raise exception 'public.hall_reservations.% is missing; run the Phase 1 migration first', required_column
        using errcode = '42703';
    end if;
  end loop;

  if to_regprocedure('public.department_manager_scope_allowed(bigint,bigint)') is null
     or to_regprocedure('public.uhms_reservation_conflict_exists(bigint,date,text,time,time,bigint)') is null
     or to_regprocedure('public.uhms_date_matches_lecture_day(date,text)') is null then
    raise exception 'Phase 1 scope/reservation helper RPC is missing; do not run this migration out of order'
      using errcode = '42883';
  end if;

  if not exists (
    select 1 from public.permissions
    where key in (
      'hall_reservations.view', 'hall_reservations.create',
      'hall_reservations.update', 'hall_reservations.cancel'
    )
    group by 1
    having count(*) = 4
  ) then
    raise exception 'Existing hall_reservations permission keys are incomplete'
      using errcode = '23514';
  end if;
end;
$$;

/* -------------------------------------------------------------------------- */
/* 1. Add reservation Scope columns without changing existing values           */
/* -------------------------------------------------------------------------- */

alter table public.hall_reservations
  add column if not exists department_id bigint;

alter table public.hall_reservations
  add column if not exists level_id bigint;

do $$
declare
  department_attnum smallint;
  level_attnum smallint;
begin
  select attnum::smallint into department_attnum
  from pg_attribute
  where attrelid = 'public.hall_reservations'::regclass
    and attname = 'department_id'
    and attnum > 0
    and not attisdropped;

  select attnum::smallint into level_attnum
  from pg_attribute
  where attrelid = 'public.hall_reservations'::regclass
    and attname = 'level_id'
    and attnum > 0
    and not attisdropped;

  if not exists (
    select 1
    from pg_attribute
    where attrelid = 'public.hall_reservations'::regclass
      and attname = 'department_id'
      and atttypid = 'int8'::regtype
      and attnum > 0
      and not attisdropped
  ) then
    raise exception 'hall_reservations.department_id must be bigint' using errcode = '42804';
  end if;

  if not exists (
    select 1
    from pg_attribute
    where attrelid = 'public.hall_reservations'::regclass
      and attname = 'level_id'
      and atttypid = 'int8'::regtype
      and attnum > 0
      and not attisdropped
  ) then
    raise exception 'hall_reservations.level_id must be bigint' using errcode = '42804';
  end if;

  if not exists (
    select 1
    from pg_constraint c
    where c.conrelid = 'public.hall_reservations'::regclass
      and c.contype = 'f'
      and c.confrelid = 'public.departments'::regclass
      and c.conkey = array[department_attnum]::smallint[]
  ) then
    execute 'alter table public.hall_reservations
      add constraint hall_reservations_department_id_fkey
      foreign key (department_id) references public.departments(id) on delete restrict';
  end if;

  if not exists (
    select 1
    from pg_constraint c
    where c.conrelid = 'public.hall_reservations'::regclass
      and c.contype = 'f'
      and c.confrelid = 'public.levels'::regclass
      and c.conkey = array[level_attnum]::smallint[]
  ) then
    execute 'alter table public.hall_reservations
      add constraint hall_reservations_level_id_fkey
      foreign key (level_id) references public.levels(id) on delete restrict';
  end if;
end;
$$;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.hall_reservations'::regclass
      and conname = 'uhms_phase2_hall_reservations_scope_pair_check'
  ) then
    execute 'alter table public.hall_reservations
      add constraint uhms_phase2_hall_reservations_scope_pair_check
      check ((department_id is null) = (level_id is null))';
  end if;
end;
$$;

create index if not exists hall_reservations_scope_idx
on public.hall_reservations(department_id, level_id, status, reservation_date, day_of_week);

/* -------------------------------------------------------------------------- */
/* 2. Validate department/level relation for every reservation write           */
/* -------------------------------------------------------------------------- */

create or replace function public.uhms_validate_hall_reservation_scope()
returns trigger
security definer
set search_path = public, pg_temp
language plpgsql
as $$
begin
  if (new.department_id is null) <> (new.level_id is null) then
    raise exception 'department_id and level_id must be supplied together' using errcode = '22023';
  end if;

  if new.department_id is not null and new.reservation_date is null then
    raise exception 'scoped hall reservations must be temporary date reservations' using errcode = '42501';
  end if;

  if new.department_id is not null and not exists (
    select 1
    from public.department_levels dl
    where dl.department_id = new.department_id
      and dl.level_id = new.level_id
      and dl.is_active = true
  ) then
    raise exception 'reservation level is not assigned to the selected department' using errcode = '42501';
  end if;

  return new;
end;
$$;

revoke all on function public.uhms_validate_hall_reservation_scope() from public, anon, authenticated;

do $$
begin
  if not exists (
    select 1
    from pg_trigger
    where tgname = 'uhms_phase2_hall_reservation_scope_guard'
      and tgrelid = 'public.hall_reservations'::regclass
      and not tgisinternal
  ) then
    execute 'create trigger uhms_phase2_hall_reservation_scope_guard
      before insert or update on public.hall_reservations
      for each row execute function public.uhms_validate_hall_reservation_scope()';
  end if;
end;
$$;

/* -------------------------------------------------------------------------- */
/* 3. Existing permission keys: grant only temporary reservation management    */
/* -------------------------------------------------------------------------- */

insert into public.role_permissions(role_key, permission_key) values
  ('department_manager', 'hall_reservations.create'),
  ('department_manager', 'hall_reservations.update'),
  ('department_manager', 'hall_reservations.cancel')
on conflict do nothing;

-- This restrictive policy narrows the existing permissive read policy. It does
-- not delete or replace Flutter/application policies.
drop policy if exists uhms_phase2_hall_reservations_scope on public.hall_reservations;
create policy uhms_phase2_hall_reservations_scope
on public.hall_reservations as restrictive
for all to authenticated
using (
  not public.is_department_manager()
  or (
    reservation_date is not null
    and department_id is not null
    and level_id is not null
    and public.department_manager_scope_allowed(department_id, level_id)
  )
)
with check (
  not public.is_department_manager()
  or (
    reservation_date is not null
    and department_id is not null
    and level_id is not null
    and public.department_manager_scope_allowed(department_id, level_id)
  )
);

/* -------------------------------------------------------------------------- */
/* 4. Scoped conflict-checking RPC                                             */
/* -------------------------------------------------------------------------- */

create or replace function public.find_hall_reservation_conflicts_scoped(
  p_hall_id bigint,
  p_reservation_date date,
  p_day_of_week text,
  p_start_at time,
  p_end_at time,
  p_department_id bigint,
  p_level_id bigint,
  p_exclude_id bigint default null
)
returns table(conflict_type text, conflict_id bigint, conflict_start time, conflict_end time)
security definer
set search_path = public, pg_temp
language plpgsql
stable
as $$
declare
  target_reservation public.hall_reservations;
  manager boolean;
  required_permission text;
begin
  if auth.uid() is null or not public.is_active_user() then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  if p_reservation_date is not null
     and p_day_of_week is not null
     and btrim(p_day_of_week) <> '' then
    raise exception 'provide either reservation_date or day_of_week, but not both' using errcode = '22023';
  end if;

  manager := public.is_department_manager();
  required_permission := case when p_exclude_id is null then 'hall_reservations.create' else 'hall_reservations.update' end;
  if not public.has_permission(required_permission) then
    raise exception 'the current user cannot manage temporary hall reservations' using errcode = '42501';
  end if;
  if manager then
    if p_reservation_date is null then
      raise exception 'Department Managers can check temporary reservations only' using errcode = '42501';
    end if;
    if p_department_id is null or p_level_id is null
       or not public.department_manager_scope_allowed(p_department_id, p_level_id) then
      raise exception 'the reservation is outside the current Scope' using errcode = '42501';
    end if;
  else
    if p_reservation_date is null and (p_day_of_week is null or btrim(p_day_of_week) = '') then
      raise exception 'provide either reservation_date or day_of_week' using errcode = '22023';
    end if;
    if p_reservation_date is not null and p_day_of_week is not null and btrim(p_day_of_week) <> '' then
      raise exception 'provide either reservation_date or day_of_week, but not both' using errcode = '22023';
    end if;
    if (p_department_id is null) <> (p_level_id is null) then
      raise exception 'department_id and level_id must be supplied together' using errcode = '22023';
    end if;
    if p_department_id is not null and p_reservation_date is null then
      raise exception 'scoped hall reservations must be temporary date reservations' using errcode = '42501';
    end if;
    if p_department_id is not null and not exists (
      select 1
      from public.department_levels dl
      where dl.department_id = p_department_id
        and dl.level_id = p_level_id
        and dl.is_active = true
    ) then
      raise exception 'reservation level is not assigned to the selected department' using errcode = '42501';
    end if;
  end if;

  if p_hall_id is null or not exists (select 1 from public.halls where id = p_hall_id) then
    raise exception 'hall does not exist' using errcode = '23503';
  end if;
  if p_day_of_week is not null
     and not public.uhms_enum_value_exists('public.lectures'::regclass, 'day_of_week', p_day_of_week) then
    raise exception 'day_of_week is not a valid value' using errcode = '22023';
  end if;
  if p_start_at is null or p_end_at is null or p_start_at >= p_end_at then
    raise exception 'start_at must be earlier than end_at' using errcode = '22023';
  end if;

  if p_exclude_id is not null and manager then
    select * into target_reservation
    from public.hall_reservations
    where id = p_exclude_id;
    if target_reservation.id is null
       or target_reservation.reservation_date is null
       or target_reservation.department_id is null
       or target_reservation.level_id is null
       or not public.department_manager_scope_allowed(target_reservation.department_id, target_reservation.level_id) then
      raise exception 'the reservation is outside the current Scope' using errcode = '42501';
    end if;
  end if;

  return query
    select 'reservation'::text, r.id, r.start_at, r.end_at
    from public.hall_reservations r
    where r.id is distinct from p_exclude_id
      and r.hall_id = p_hall_id
      and r.status = 'active'
      and p_start_at < r.end_at
      and p_end_at > r.start_at
      and (
        (p_reservation_date is not null and r.reservation_date = p_reservation_date)
        or (p_reservation_date is not null and r.reservation_date is null and public.uhms_date_matches_lecture_day(p_reservation_date, r.day_of_week))
        or (p_reservation_date is null and r.reservation_date is not null and public.uhms_date_matches_lecture_day(r.reservation_date, p_day_of_week))
        or (p_reservation_date is null and r.reservation_date is null and r.day_of_week = p_day_of_week)
      )
    union all
    select 'lecture'::text, l.id, l.start_at, l.end_at
    from public.lectures l
    where l.canceled = false
      and l.hall_id = p_hall_id
      and p_start_at < l.end_at
      and p_end_at > l.start_at
      and (
        (p_reservation_date is null and l.day_of_week::text = p_day_of_week)
        or (
          p_reservation_date is not null
          and public.uhms_date_matches_lecture_day(p_reservation_date, l.day_of_week::text)
          and not exists (
            select 1
            from public.lecture_occurrence_overrides o
            where o.lecture_id = l.id
              and o.occurrence_date = p_reservation_date
          )
        )
      );
end;
$$;

grant execute on function public.find_hall_reservation_conflicts_scoped(bigint, date, text, time, time, bigint, bigint, bigint) to authenticated;
revoke execute on function public.find_hall_reservation_conflicts_scoped(bigint, date, text, time, time, bigint, bigint, bigint) from public, anon;

-- The old five-argument conflict RPC remains available to existing global
-- clients, but it cannot be used by a Department Manager without a Scope payload.
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
begin
  if public.is_department_manager() then
    raise exception 'Department Managers must use the scoped reservation conflict check' using errcode = '42501';
  end if;

  return query
    select *
    from public.find_hall_reservation_conflicts_scoped(
      p_hall_id, null, p_day_of_week,
      p_start_at, p_end_at, null, null, p_exclude_id
    );
end;
$$;

grant execute on function public.find_hall_reservation_conflicts(bigint, text, time, time, bigint) to authenticated;
revoke execute on function public.find_hall_reservation_conflicts(bigint, text, time, time, bigint) from public, anon;

-- Preserve the existing v2 signature for global roles. A Department Manager
-- must use the scoped RPC so a missing Scope cannot be inferred or bypassed.
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
begin
  if public.is_department_manager() then
    raise exception 'Department Managers must use the scoped reservation conflict check' using errcode = '42501';
  end if;

  return query
    select *
    from public.find_hall_reservation_conflicts_scoped(
      p_hall_id, p_reservation_date, p_day_of_week,
      p_start_at, p_end_at, null, null, p_exclude_id
    );
end;
$$;

grant execute on function public.find_hall_reservation_conflicts_v2(bigint, date, text, time, time, bigint) to authenticated;
revoke execute on function public.find_hall_reservation_conflicts_v2(bigint, date, text, time, time, bigint) from public, anon;

/* -------------------------------------------------------------------------- */
/* 5. Scoped save/status RPCs                                                  */
/* -------------------------------------------------------------------------- */

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
  department_value bigint;
  level_value bigint;
  day_value text;
  start_value time;
  end_value time;
  reason_value text;
  notes_value text;
  required_permission text;
  manager boolean;
begin
  if auth.uid() is null or not public.is_active_user() then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'reservation payload must be a JSON object' using errcode = '22023';
  end if;

  manager := public.is_department_manager();
  required_permission := case when p_reservation_id is null then 'hall_reservations.create' else 'hall_reservations.update' end;
  if not public.has_permission(required_permission) then
    raise exception 'the current user cannot manage hall reservations' using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(918273645::bigint);

  if p_reservation_id is not null then
    select * into current_reservation
    from public.hall_reservations
    where id = p_reservation_id
    for update;
    if current_reservation.id is null then
      raise exception 'reservation was not found' using errcode = 'P0002';
    end if;

    if manager and (
      current_reservation.reservation_date is null
      or current_reservation.department_id is null
      or current_reservation.level_id is null
      or not public.department_manager_scope_allowed(current_reservation.department_id, current_reservation.level_id)
    ) then
      raise exception 'the reservation is outside the current Scope' using errcode = '42501';
    end if;
  end if;

  if (p_payload ->> 'hall_id') !~ '^[1-9][0-9]*$' then
    raise exception 'hall_id must be a positive integer' using errcode = '22023';
  end if;
  hall_value := (p_payload ->> 'hall_id')::bigint;
  if not exists (select 1 from public.halls where id = hall_value) then
    raise exception 'hall does not exist' using errcode = '23503';
  end if;

  if p_payload ? 'reservation_date'
     and jsonb_typeof(p_payload -> 'reservation_date') = 'string'
     and btrim(p_payload ->> 'reservation_date') <> '' then
    begin
      reservation_date_value := (p_payload ->> 'reservation_date')::date;
    exception when others then
      raise exception 'reservation_date must be a valid date' using errcode = '22023';
    end;
  else
    reservation_date_value := null;
  end if;

  day_value := nullif(btrim(p_payload ->> 'day_of_week'), '');
  if (reservation_date_value is null) = (day_value is null) then
    raise exception 'provide either reservation_date or day_of_week, but not both' using errcode = '22023';
  end if;
  if day_value is not null
     and not public.uhms_enum_value_exists('public.lectures'::regclass, 'day_of_week', day_value) then
    raise exception 'day_of_week is not a valid value' using errcode = '22023';
  end if;

  if p_payload ? 'department_id'
     and jsonb_typeof(p_payload -> 'department_id') not in ('number', 'null') then
    raise exception 'department_id must be a number or null' using errcode = '22023';
  end if;
  if p_payload ? 'department_id'
     and jsonb_typeof(p_payload -> 'department_id') = 'number' then
    if coalesce((p_payload ->> 'department_id') !~ '^[1-9][0-9]*$', true) then
      raise exception 'department_id must be a positive integer' using errcode = '22023';
    end if;
    department_value := (p_payload ->> 'department_id')::bigint;
  else
    department_value := null;
  end if;

  if p_payload ? 'level_id'
     and jsonb_typeof(p_payload -> 'level_id') not in ('number', 'null') then
    raise exception 'level_id must be a number or null' using errcode = '22023';
  end if;
  if p_payload ? 'level_id'
     and jsonb_typeof(p_payload -> 'level_id') = 'number' then
    if coalesce((p_payload ->> 'level_id') !~ '^[1-9][0-9]*$', true) then
      raise exception 'level_id must be a positive integer' using errcode = '22023';
    end if;
    level_value := (p_payload ->> 'level_id')::bigint;
  else
    level_value := null;
  end if;

  if (department_value is null) <> (level_value is null) then
    raise exception 'department_id and level_id must be supplied together' using errcode = '22023';
  end if;
  if department_value is not null and reservation_date_value is null then
    raise exception 'scoped hall reservations must be temporary date reservations' using errcode = '42501';
  end if;

  if manager then
    if reservation_date_value is null then
      raise exception 'Department Managers can manage temporary reservations only' using errcode = '42501';
    end if;
    if department_value is null or level_value is null
       or not public.department_manager_scope_allowed(department_value, level_value) then
      raise exception 'the reservation is outside the current Scope' using errcode = '42501';
    end if;
  elsif department_value is not null and not exists (
    select 1
    from public.department_levels dl
    where dl.department_id = department_value
      and dl.level_id = level_value
      and dl.is_active = true
  ) then
    raise exception 'reservation level is not assigned to the selected department' using errcode = '42501';
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

  if p_reservation_id is null or current_reservation.status = 'active' then
    if public.uhms_reservation_conflict_exists(
      hall_value, reservation_date_value, day_value,
      start_value, end_value, p_reservation_id
    ) then
      raise exception 'لا يمكن حفظ الحجز: يوجد حجز آخر متداخل للقاعة' using errcode = 'P0001';
    end if;

    if exists (
      select 1
      from public.lectures l
      where l.canceled = false
        and l.hall_id = hall_value
        and start_value < l.end_at
        and end_value > l.start_at
        and (
          (reservation_date_value is null and l.day_of_week::text = day_value)
          or (
            reservation_date_value is not null
            and public.uhms_date_matches_lecture_day(reservation_date_value, l.day_of_week::text)
            and not exists (
              select 1
              from public.lecture_occurrence_overrides o
              where o.lecture_id = l.id
                and o.occurrence_date = reservation_date_value
            )
          )
        )
    ) then
      if reservation_date_value is not null then
        raise exception 'لا يمكن حفظ الحجز: القاعة مشغولة بمحاضرة في هذا التاريخ والوقت؛ يجب إلغاء occurrence لهذا اليوم أولًا' using errcode = 'P0001';
      else
        raise exception 'لا يمكن حفظ الحجز: القاعة مشغولة بمحاضرة في هذا الوقت' using errcode = 'P0001';
      end if;
    end if;
  end if;

  if p_reservation_id is null then
    insert into public.hall_reservations(
      hall_id, reservation_date, day_of_week, department_id, level_id,
      start_at, end_at, status, reason, notes, created_by, updated_by
    )
    values (
      hall_value, reservation_date_value, day_value, department_value, level_value,
      start_value, end_value, 'active', reason_value, notes_value, auth.uid(), auth.uid()
    )
    returning * into saved_reservation;
  else
    update public.hall_reservations
    set hall_id = hall_value,
        reservation_date = reservation_date_value,
        day_of_week = day_value,
        department_id = department_value,
        level_id = level_value,
        start_at = start_value,
        end_at = end_value,
        reason = reason_value,
        notes = notes_value,
        updated_by = auth.uid(),
        updated_at = now()
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
  clean_reason text := nullif(btrim(coalesce(p_reason, '')), '');
  conflict_on_lecture boolean;
begin
  if auth.uid() is null or not public.is_active_user() then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if not public.has_permission('hall_reservations.cancel') then
    raise exception 'the current user cannot change reservation status' using errcode = '42501';
  end if;
  if p_reservation_id is null or p_reservation_id <= 0
     or p_status not in ('active', 'canceled') then
    raise exception 'reservation id or status is invalid' using errcode = '22023';
  end if;
  if clean_reason is not null and char_length(clean_reason) > 500 then
    raise exception 'reason must not exceed 500 characters' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(918273645::bigint);

  select * into target_reservation
  from public.hall_reservations
  where id = p_reservation_id
  for update;
  if target_reservation.id is null then
    raise exception 'reservation was not found' using errcode = 'P0002';
  end if;

  if public.is_department_manager() and (
    target_reservation.reservation_date is null
    or target_reservation.department_id is null
    or target_reservation.level_id is null
    or not public.department_manager_scope_allowed(target_reservation.department_id, target_reservation.level_id)
  ) then
    raise exception 'the reservation is outside the current Scope' using errcode = '42501';
  end if;

  if target_reservation.status = p_status then
    return target_reservation;
  end if;

  if p_status = 'active' then
    if exists (
      select 1 from public.halls
      where id = target_reservation.hall_id and booking = true
    ) then
      raise exception 'لا يمكن تفعيل الحجز لأن القاعة غير متاحة إداريًا' using errcode = 'P0001';
    end if;

    if public.uhms_reservation_conflict_exists(
      target_reservation.hall_id,
      target_reservation.reservation_date,
      target_reservation.day_of_week,
      target_reservation.start_at,
      target_reservation.end_at,
      target_reservation.id
    ) then
      raise exception 'لا يمكن تفعيل الحجز: يوجد حجز آخر متداخل' using errcode = 'P0001';
    end if;

    conflict_on_lecture := exists (
      select 1
      from public.lectures l
      where l.canceled = false
        and l.hall_id = target_reservation.hall_id
        and target_reservation.start_at < l.end_at
        and target_reservation.end_at > l.start_at
        and (
          (target_reservation.reservation_date is null and l.day_of_week::text = target_reservation.day_of_week)
          or (
            target_reservation.reservation_date is not null
            and public.uhms_date_matches_lecture_day(target_reservation.reservation_date, l.day_of_week::text)
            and not exists (
              select 1
              from public.lecture_occurrence_overrides o
              where o.lecture_id = l.id
                and o.occurrence_date = target_reservation.reservation_date
            )
          )
        )
    );
    if conflict_on_lecture then
      if target_reservation.reservation_date is not null then
        raise exception 'لا يمكن تفعيل الحجز: القاعة مشغولة بمحاضرة في هذا التاريخ والوقت؛ يجب إلغاء occurrence لهذا اليوم أولًا' using errcode = 'P0001';
      else
        raise exception 'لا يمكن تفعيل الحجز: القاعة مشغولة بمحاضرة في هذا الوقت' using errcode = 'P0001';
      end if;
    end if;
  end if;

  update public.hall_reservations
  set status = p_status,
      reason = coalesce(clean_reason, reason),
      updated_by = auth.uid(),
      updated_at = now()
  where id = target_reservation.id
  returning * into updated_reservation;

  return updated_reservation;
end;
$$;

grant execute on function public.set_hall_reservation_status(bigint, text, text) to authenticated;
revoke execute on function public.set_hall_reservation_status(bigint, text, text) from public, anon;
