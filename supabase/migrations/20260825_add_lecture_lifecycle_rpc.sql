-- Incremental migration for an already-deployed installation.
-- Run this file only if functions.sql was already executed before the lifecycle fix.
-- It adds the RPC used by the React UI for cancel/reactivate; it does not change rows.

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

  if target_lecture.canceled = p_canceled then
    return target_lecture;
  end if;

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
