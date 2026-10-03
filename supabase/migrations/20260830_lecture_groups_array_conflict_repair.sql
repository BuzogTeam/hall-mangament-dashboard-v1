-- Repair migration for the current lectures schema where the old `group`
-- column was replaced by an integer-like array column named `groups`.
--
-- It restores database conflict protection without deleting or changing
-- academic rows. Hall and instructor conflicts remain global. Batch conflicts
-- are rejected only when the two groups arrays overlap.
--
-- Run after the already-applied Phase 1 migrations and after the database owner
-- confirms that public.lectures.groups is the current array column.

/* -------------------------------------------------------------------------- */
/* 0. Fail-closed schema check                                                  */
/* -------------------------------------------------------------------------- */

do $$
begin
  if to_regclass('public.lectures') is null then
    raise exception 'public.lectures is missing' using errcode = '42P01';
  end if;

  if not exists (
    select 1
    from pg_attribute a
    join pg_type t on t.oid = a.atttypid
    where a.attrelid = 'public.lectures'::regclass
      and a.attname = 'groups'
      and a.attnum > 0
      and not a.attisdropped
      and t.typelem <> 0
  ) then
    raise exception 'public.lectures.groups must exist and be an array column' using errcode = '42804';
  end if;

  if to_regprocedure('public.uhms_enum_value_exists(regclass,name,text)') is null
     or to_regprocedure('public.has_permission(text)') is null
     or to_regprocedure('public.is_active_user()') is null then
    raise exception 'required schedule security helper is missing' using errcode = '42883';
  end if;
end;
$$;

/* -------------------------------------------------------------------------- */
/* 1. Array payload validation                                                  */
/* -------------------------------------------------------------------------- */

create or replace function public.uhms_groups_json_to_pg_literal(p_groups jsonb)
returns text
security definer
set search_path = public, pg_temp
language plpgsql
immutable
as $$
declare
  literal text;
begin
  if p_groups is null or jsonb_typeof(p_groups) <> 'array' or jsonb_array_length(p_groups) = 0 then
    raise exception 'groups must be a non-empty JSON array' using errcode = '22023';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_groups) as items(value)
    where jsonb_typeof(items.value) <> 'number'
       or coalesce((items.value #>> '{}') !~ '^[1-9][0-9]*$', true)
  ) then
    raise exception 'groups must contain positive integer values' using errcode = '22023';
  end if;

  select '{' || string_agg(items.value #>> '{}', ',' order by items.ordinality) || '}'
    into literal
  from jsonb_array_elements(p_groups) with ordinality as items(value, ordinality);

  return literal;
end;
$$;

revoke all on function public.uhms_groups_json_to_pg_literal(jsonb) from public, anon, authenticated;

/* -------------------------------------------------------------------------- */
/* 2. Restore the database conflict trigger with group-array semantics          */
/* -------------------------------------------------------------------------- */

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

  if new.canceled then
    return new;
  end if;

  if new.groups is null or cardinality(new.groups) = 0 then
    raise exception 'groups must contain at least one group' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(918273645::bigint);

  if exists (select 1 from public.halls where id = new.hall_id and booking = true) then
    raise exception 'لا يمكن حفظ المحاضرة: القاعة غير متاحة للجدولة' using errcode = 'P0001';
  end if;

  if exists (
    select 1
    from public.hall_reservations r
    where r.hall_id = new.hall_id
      and r.status = 'active'
      and (
        (r.reservation_date is null and r.day_of_week = new.day_of_week::text)
        or (
          r.reservation_date is not null
          and public.uhms_date_matches_lecture_day(r.reservation_date, new.day_of_week::text)
          and not exists (
            select 1
            from public.lecture_occurrence_overrides o
            where o.lecture_id = new.id
              and o.occurrence_date = r.reservation_date
          )
        )
      )
      and new.start_at < r.end_at
      and new.end_at > r.start_at
  ) then
    raise exception 'لا يمكن حفظ المحاضرة: القاعة محجوزة في هذا الوقت' using errcode = 'P0001';
  end if;

  if tg_op = 'UPDATE'
     and old.day_of_week is not distinct from new.day_of_week
     and old.start_at is not distinct from new.start_at
     and old.end_at is not distinct from new.end_at
     and old.hall_id is not distinct from new.hall_id
     and old.instructor_id is not distinct from new.instructor_id
     and old.batch_id is not distinct from new.batch_id
     and old.groups::text is not distinct from new.groups::text
     and old.canceled is not distinct from new.canceled then
    return new;
  end if;

  if exists (
    select 1
    from public.lectures l
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
    select 1
    from public.lectures l
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
    select 1
    from public.lectures l
    where l.id <> new.id
      and l.canceled = false
      and l.day_of_week = new.day_of_week
      and l.batch_id = new.batch_id
      and l.groups is not null
      and l.groups && new.groups
      and new.start_at < l.end_at
      and new.end_at > l.start_at
  ) then
    raise exception 'لا يمكن حفظ المحاضرة: يوجد تعارض في الدفعة ونفس المجموعة' using errcode = 'P0001';
  end if;

  return new;
end;
$$;

revoke all on function public.uhms_validate_lecture_conflicts() from public, anon, authenticated;

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

/* -------------------------------------------------------------------------- */
/* 3. Atomic lecture save using groups[]                                       */
/* -------------------------------------------------------------------------- */

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
  groups_type text;
  day_value text;
  start_value time;
  end_value time;
  groups_literal text;
  subject_value bigint;
  hall_value bigint;
  instructor_value bigint;
  batch_value bigint;
  schedule_changed boolean := true;
  batch_conflict boolean := false;
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
  if day_value is null or day_value = '' then
    raise exception 'day_of_week is required' using errcode = '22023';
  end if;
  if not public.uhms_enum_value_exists('public.lectures'::regclass, 'day_of_week', day_value) then
    raise exception 'day_of_week is not a valid value' using errcode = '22023';
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

  groups_literal := public.uhms_groups_json_to_pg_literal(p_payload -> 'groups');

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
    select 1
    from public.hall_reservations r
    where r.hall_id = hall_value
      and r.status = 'active'
      and (
        (r.reservation_date is null and r.day_of_week = day_value)
        or (
          r.reservation_date is not null
          and public.uhms_date_matches_lecture_day(r.reservation_date, day_value)
          and not exists (
            select 1 from public.lecture_occurrence_overrides o
            where o.lecture_id = p_lecture_id
              and o.occurrence_date = r.reservation_date
          )
        )
      )
      and start_value < r.end_at
      and end_value > r.start_at
  ) then
    raise exception 'لا يمكن حفظ المحاضرة: القاعة محجوزة في هذا الوقت' using errcode = 'P0001';
  end if;

  if public.is_department_manager() and not exists (
    select 1
    from public.batches b
    where b.id = batch_value
      and public.department_manager_scope_allowed(b.department_id, b.level_id)
  ) then
    raise exception 'the batch is outside the current department' using errcode = '42501';
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
    into groups_type
  from pg_attribute a
  join pg_type t on t.oid = a.atttypid
  join pg_namespace n on n.oid = t.typnamespace
  where a.attrelid = 'public.lectures'::regclass
    and a.attname = 'groups'
    and t.typelem <> 0
    and a.attnum > 0
    and not a.attisdropped;

  if groups_type is null then
    raise exception 'lectures.groups array type could not be resolved' using errcode = '42804';
  end if;

  if p_lecture_id is not null then
    schedule_changed := current_lecture.day_of_week::text is distinct from day_value
      or current_lecture.start_at is distinct from start_value
      or current_lecture.end_at is distinct from end_value
      or current_lecture.hall_id is distinct from hall_value
      or current_lecture.instructor_id is distinct from instructor_value
      or current_lecture.batch_id is distinct from batch_value
      or current_lecture.groups::text is distinct from groups_literal;
  end if;

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

    execute format(
      'select exists (
         select 1 from public.lectures l
         where ( $1 is null or l.id <> $1 )
           and l.canceled = false
           and l.day_of_week::text = $2
           and l.batch_id = $3
           and l.groups is not null
           and l.groups && $4::%s
           and $5 < l.end_at and $6 > l.start_at
       )',
      groups_type
    ) into batch_conflict
    using p_lecture_id, day_value, batch_value, groups_literal, start_value, end_value;
    if batch_conflict then conflict_message := conflict_message || 'الدفعة ونفس المجموعة، '; end if;

    if conflict_message <> 'لا يمكن حفظ المحاضرة بسبب: ' then
      raise exception '%', rtrim(conflict_message, '، ') using errcode = 'P0001';
    end if;
  end if;

  if p_lecture_id is null then
    execute format(
      'insert into public.lectures (day_of_week,start_at,end_at,subject_id,hall_id,instructor_id,canceled,groups,batch_id,updated_at)
       values ($1::%1$s,$2,$3,$4,$5,$6,false,$7::%2$s,$8,now()) returning *',
      day_type, groups_type
    ) into saved_lecture
    using day_value, start_value, end_value, subject_value, hall_value, instructor_value, groups_literal, batch_value;
  else
    execute format(
      'update public.lectures set day_of_week=$1::%1$s,start_at=$2,end_at=$3,subject_id=$4,hall_id=$5,instructor_id=$6,groups=$7::%2$s,batch_id=$8,updated_at=now() where id=$9 returning *',
      day_type, groups_type
    ) into saved_lecture
    using day_value, start_value, end_value, subject_value, hall_value, instructor_value, groups_literal, batch_value, p_lecture_id;
  end if;

  if saved_lecture.id is null then
    raise exception 'lecture was not saved' using errcode = 'P0002';
  end if;
  return saved_lecture;
end;
$$;

grant execute on function public.save_lecture_atomic(bigint,jsonb) to authenticated;
revoke execute on function public.save_lecture_atomic(bigint,jsonb) from public, anon;

/* -------------------------------------------------------------------------- */
/* 4. Group-aware conflict preflight RPC                                       */
/* -------------------------------------------------------------------------- */

create or replace function public.find_lecture_conflicts_v2(
  p_day_of_week text,
  p_start_at time,
  p_end_at time,
  p_hall_id bigint,
  p_instructor_id bigint,
  p_batch_id bigint,
  p_groups jsonb,
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
  groups_literal text;
  groups_type text;
begin
  if auth.uid() is null or not public.is_active_user() then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  required_permission := case when p_exclude_id is null then 'lectures.create' else 'lectures.update' end;
  if not public.has_permission(required_permission) then
    raise exception 'the current user cannot manage this lecture' using errcode = '42501';
  end if;
  if p_day_of_week is null or btrim(p_day_of_week) = '' then
    raise exception 'p_day_of_week is required' using errcode = '22023';
  end if;
  if not public.uhms_enum_value_exists('public.lectures'::regclass, 'day_of_week', p_day_of_week) then
    raise exception 'day_of_week is not a valid value' using errcode = '22023';
  end if;
  if p_start_at is null or p_end_at is null or p_start_at >= p_end_at then
    raise exception 'p_start_at must be earlier than p_end_at' using errcode = '22023';
  end if;
  if p_hall_id is null or not exists (select 1 from public.halls where id = p_hall_id) then
    raise exception 'p_hall_id does not reference an existing hall' using errcode = '23503';
  end if;
  if p_instructor_id is null or not exists (select 1 from public.instructors where id = p_instructor_id) then
    raise exception 'p_instructor_id does not reference an existing instructor' using errcode = '23503';
  end if;
  if p_batch_id is null or not exists (select 1 from public.batches where id = p_batch_id) then
    raise exception 'p_batch_id does not reference an existing batch' using errcode = '23503';
  end if;

  groups_literal := public.uhms_groups_json_to_pg_literal(p_groups);
  select format('%I.%I', n.nspname, t.typname)
    into groups_type
  from pg_attribute a
  join pg_type t on t.oid = a.atttypid
  join pg_namespace n on n.oid = t.typnamespace
  where a.attrelid = 'public.lectures'::regclass
    and a.attname = 'groups'
    and t.typelem <> 0
    and a.attnum > 0
    and not a.attisdropped;

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

  return query execute format(
    'select ''hall''::text,null::bigint,null::time,null::time,null::bigint,null::bigint,null::bigint,null::bigint
     from public.lectures l
     where l.canceled=false and l.day_of_week::text=$1 and l.hall_id=$4
       and ($8 is null or l.id<>$8) and $2<l.end_at and $3>l.start_at
     union all
     select ''instructor''::text,null::bigint,null::time,null::time,null::bigint,null::bigint,null::bigint,null::bigint
     from public.lectures l
     where l.canceled=false and l.day_of_week::text=$1 and l.instructor_id=$5
       and ($8 is null or l.id<>$8) and $2<l.end_at and $3>l.start_at
     union all
     select ''batch''::text,null::bigint,null::time,null::time,null::bigint,null::bigint,null::bigint,null::bigint
     from public.lectures l
     where l.canceled=false and l.day_of_week::text=$1 and l.batch_id=$6
       and l.groups is not null and l.groups && $7::%s
       and ($8 is null or l.id<>$8) and $2<l.end_at and $3>l.start_at',
    groups_type
  ) using p_day_of_week,p_start_at,p_end_at,p_hall_id,p_instructor_id,p_batch_id,groups_literal,p_exclude_id;
end;
$$;

grant execute on function public.find_lecture_conflicts_v2(text,time,time,bigint,bigint,bigint,jsonb,bigint) to authenticated;
revoke execute on function public.find_lecture_conflicts_v2(text,time,time,bigint,bigint,bigint,jsonb,bigint) from public, anon;

/* -------------------------------------------------------------------------- */
/* 5. Group-aware Conflict Center and trigger                                  */
/* -------------------------------------------------------------------------- */

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
  select 'hall'::text,a.id,b.id,a.day_of_week::text,
         greatest(a.start_at,b.start_at),least(a.end_at,b.end_at),a.hall_id
  from visible_lectures a
  join visible_lectures b
    on a.id < b.id
   and a.day_of_week = b.day_of_week
   and a.hall_id = b.hall_id
   and a.start_at < b.end_at and a.end_at > b.start_at
  union all
  select 'instructor'::text,a.id,b.id,a.day_of_week::text,
         greatest(a.start_at,b.start_at),least(a.end_at,b.end_at),a.instructor_id
  from visible_lectures a
  join visible_lectures b
    on a.id < b.id
   and a.day_of_week = b.day_of_week
   and a.instructor_id = b.instructor_id
   and a.start_at < b.end_at and a.end_at > b.start_at
  union all
  select 'batch'::text,a.id,b.id,a.day_of_week::text,
         greatest(a.start_at,b.start_at),least(a.end_at,b.end_at),a.batch_id
  from visible_lectures a
  join visible_lectures b
    on a.id < b.id
   and a.day_of_week = b.day_of_week
   and a.batch_id = b.batch_id
   and a.groups is not null and b.groups is not null
   and a.groups && b.groups
   and a.start_at < b.end_at and a.end_at > b.start_at;
end;
$$;

grant execute on function public.find_all_lecture_conflicts() to authenticated;
revoke execute on function public.find_all_lecture_conflicts() from public, anon;
