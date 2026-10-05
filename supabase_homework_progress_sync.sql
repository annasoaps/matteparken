-- Matteparken: sync homework completion to Supabase/Admin
-- Run once in Supabase SQL Editor.
-- Adds a dedicated student RPC that marks one homework assignment complete
-- after the client has received a valid full-round completion event.

create or replace function public.matteparken_current_student_id()
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_col text;
  v_student uuid;
begin
  if v_uid is null then
    return null;
  end if;

  for v_col in
    select c.column_name
    from information_schema.columns c
    where c.table_schema = 'public'
      and c.table_name = 'students'
      and c.data_type = 'uuid'
      and c.column_name not in ('id','class_id')
    order by
      case c.column_name
        when 'claimed_by' then 1
        when 'auth_user_id' then 2
        when 'user_id' then 3
        when 'claimed_by_user_id' then 4
        when 'session_user_id' then 5
        when 'owner_id' then 6
        else 50
      end,
      c.column_name
  loop
    execute format('select id from public.students where %I = $1 limit 1', v_col)
      into v_student
      using v_uid;
    if v_student is not null then
      return v_student;
    end if;
  end loop;

  return null;
end;
$$;

revoke all on function public.matteparken_current_student_id() from public;
grant execute on function public.matteparken_current_student_id() to authenticated;

create or replace function public.student_complete_homework_assignment(
  p_assignment_id uuid,
  p_game_id text,
  p_round_type text,
  p_table integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_student uuid := public.matteparken_current_student_id();
  v_student_class uuid;
  v_assignment record;
  v_expected text;
  v_assignment_table integer;
  v_completed_at timestamptz;
begin
  if v_student is null then
    return jsonb_build_object('ok',false,'reason','no_student_session');
  end if;

  select class_id
    into v_student_class
  from public.students
  where id = v_student;

  select id,class_id,game_id,game_config,homework_id,enabled
    into v_assignment
  from public.assignments
  where id = p_assignment_id;

  if not found then
    return jsonb_build_object('ok',false,'reason','assignment_not_found');
  end if;

  if v_assignment.class_id is distinct from v_student_class then
    return jsonb_build_object('ok',false,'reason','forbidden');
  end if;

  if v_assignment.homework_id is null or coalesce(v_assignment.enabled,false) = false then
    return jsonb_build_object('ok',false,'reason','not_active_homework_assignment');
  end if;

  if trim(coalesce(p_game_id,'')) <> v_assignment.game_id then
    return jsonb_build_object('ok',false,'reason','game_mismatch');
  end if;

  v_expected := case v_assignment.game_id
    when 'multiplication' then 'table-round'
    when 'equations' then 'solved-random-equation'
    when 'pow10' then 'ten-question-round'
    when 'fractionDecimal' then 'matching-board'
    when 'fractionArithmetic' then 'three-calculation-round'
    when 'percentConvert' then 'six-trio-round'
    when 'sharePart' then 'ten-question-round'
    when 'prefixMatch' then 'ten-question-round'
    when 'unitConvert' then 'ten-question-round'
    when 'statistics' then 'ten-question-round'
    when 'scientificNotation' then 'ten-question-round'
    else null
  end;

  if v_expected is null then
    return jsonb_build_object('ok',false,'reason','unsupported_game');
  end if;

  if v_assignment.game_id = 'percentConvert' then
    if trim(coalesce(p_round_type,'')) not in ('six-trio-round','ten-question-round') then
      return jsonb_build_object('ok',false,'reason','round_type_mismatch');
    end if;
  elsif trim(coalesce(p_round_type,'')) <> v_expected then
    return jsonb_build_object('ok',false,'reason','round_type_mismatch');
  end if;

  if v_assignment.game_id = 'multiplication'
     and coalesce(v_assignment.game_config->>'table','') ~ '^(10|[1-9])$' then
    v_assignment_table := (v_assignment.game_config->>'table')::integer;
    if p_table is distinct from v_assignment_table then
      return jsonb_build_object('ok',false,'reason','table_mismatch');
    end if;
  end if;

  update public.student_assignment_progress
     set completed = greatest(coalesce(completed,0),1),
         last_active = now(),
         updated_at = now(),
         completed_at = coalesce(completed_at,now())
   where student_id = v_student
     and assignment_id = p_assignment_id;

  if not found then
    insert into public.student_assignment_progress(
      student_id,assignment_id,completed,last_active,updated_at,completed_at
    )
    values (
      v_student,p_assignment_id,1,now(),now(),now()
    );
  end if;

  select completed_at
    into v_completed_at
  from public.student_assignment_progress
  where student_id = v_student
    and assignment_id = p_assignment_id;

  return jsonb_build_object(
    'ok',true,
    'done',true,
    'completed',1,
    'completed_at',v_completed_at
  );
end;
$$;

revoke all on function public.student_complete_homework_assignment(uuid,text,text,integer) from public;
grant execute on function public.student_complete_homework_assignment(uuid,text,text,integer) to authenticated;
