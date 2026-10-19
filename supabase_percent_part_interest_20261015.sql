-- Matteparken: support for percentPart and interest, 2026-10-15.
-- Review and run once in Supabase SQL Editor before enabling teacher assignments.
-- Based on the functions installed in the connected project at preparation time.
-- Existing authentication, student-ownership checks and rate-limits preserved.

CREATE OR REPLACE FUNCTION public.student_claim_math_cones(p_game_id text, p_activity_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_student uuid := public.matteparken_current_student_id();
  v_today date := (now() at time zone 'Europe/Stockholm')::date;
  v_required integer;
  v_count integer := 0;
  v_claimed integer := 0;
  v_available integer := 0;
  v_new_units integer := 0;
  v_reward integer := 0;
  v_balance integer := 0;
begin
  if v_student is null then
    return jsonb_build_object('ok',false,'reason','no_student_session');
  end if;

  p_game_id := trim(coalesce(p_game_id,''));
  p_activity_key := trim(coalesce(p_activity_key,''));

  if p_game_id = 'multiplication' and p_activity_key ~ '^multiplication:(10|[1-9])$' then
    v_required := 10;
  elsif p_game_id = 'equations' and p_activity_key = 'equations' then
    v_required := 3;
  elsif p_game_id = 'fractionArithmetic' and p_activity_key = 'fractionArithmetic' then
    v_required := 3;
  elsif p_game_id = 'fractionDecimal' and p_activity_key = 'fractionDecimal' then
    v_required := 8;
  elsif p_game_id = 'percentConvert' and p_activity_key = 'percentConvert' then
    v_required := 6;
  elsif p_game_id = 'percentChange' and p_activity_key = 'percentChange' then
    v_required := 3;
  elsif p_game_id = 'whole' and p_activity_key = 'whole' then
    v_required := 4;
  elsif p_game_id in ('percentPart','interest') and p_activity_key = p_game_id then
    v_required := 4;
  elsif p_game_id in ('pow10','mgn','sharePart','prefixMatch','unitConvert','statistics','scientificNotation')
        and p_activity_key = p_game_id then
    v_required := 10;
  else
    return jsonb_build_object('ok',false,'reason','unsupported_activity');
  end if;

  select coalesce(sum(a.count),0)::integer
    into v_count
  from public.student_daily_activity a
  where a.student_id = v_student
    and a.activity_date = v_today
    and a.game_id = p_game_id
    and a.activity_key = p_activity_key;

  v_available := floor(v_count::numeric / v_required)::integer;

  insert into public.student_cone_claims(student_id,activity_date,activity_key,claimed_units)
  values (v_student,v_today,p_activity_key,0)
  on conflict (student_id,activity_date,activity_key) do nothing;

  select claimed_units into v_claimed
  from public.student_cone_claims
  where student_id=v_student and activity_date=v_today and activity_key=p_activity_key
  for update;

  v_new_units := greatest(0, v_available - v_claimed);

  perform public.matteparken_ensure_cones(v_student);

  if v_new_units = 0 then
    select balance into v_balance from public.student_cones where student_id=v_student;
    return jsonb_build_object('ok',true,'granted',false,'balance',v_balance);
  end if;

  v_reward := v_new_units * 10;

  update public.student_cone_claims
     set claimed_units=v_available,updated_at=now()
   where student_id=v_student and activity_date=v_today and activity_key=p_activity_key;

  update public.student_cones
     set balance=balance+v_reward,updated_at=now()
   where student_id=v_student
   returning balance into v_balance;

  return jsonb_build_object('ok',true,'granted',true,'amount',v_reward,'balance',v_balance);
end;
$function$;


CREATE OR REPLACE FUNCTION public.student_complete_homework_assignment(p_assignment_id uuid, p_game_id text, p_round_type text, p_table integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    when 'percentChange' then 'three-change-round'
    when 'whole' then 'four-whole-round'
    when 'percentPart' then 'four-part-round'
    when 'interest' then 'four-interest-round'
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
$function$;


CREATE OR REPLACE FUNCTION public.record_percent_part_interest_round(p_assignment_id uuid, p_game_id text, p_round_type text, p_table integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_student uuid := public.matteparken_current_student_id();
  v_class uuid;
  v_assignment record;
  v_completed integer := 0;
  v_completed_at timestamptz := null;
  v_target integer := 1;
begin
  if v_student is null then
    return jsonb_build_object('ok',false,'reason','no_student_session');
  end if;

  select class_id into v_class from public.students where id = v_student;

  select id,class_id,game_id,homework_id,enabled,target
    into v_assignment
  from public.assignments
  where id = p_assignment_id;
  if not found then
    return jsonb_build_object('ok',false,'reason','assignment_not_found');
  end if;
  if v_assignment.class_id is distinct from v_class then
    return jsonb_build_object('ok',false,'reason','forbidden');
  end if;
  if coalesce(v_assignment.enabled,false) = false or v_assignment.homework_id is not null then
    return jsonb_build_object('ok',false,'reason','not_active_daily_assignment');
  end if;
  if v_assignment.game_id not in ('percentPart','interest')
     or trim(coalesce(p_game_id,'')) <> v_assignment.game_id then
    return jsonb_build_object('ok',false,'reason','game_mismatch');
  end if;
  if (v_assignment.game_id = 'percentPart' and trim(coalesce(p_round_type,'')) <> 'four-part-round')
     or (v_assignment.game_id = 'interest' and trim(coalesce(p_round_type,'')) <> 'four-interest-round') then
    return jsonb_build_object('ok',false,'reason','round_type_mismatch');
  end if;

  v_target := greatest(1,coalesce(v_assignment.target,1));

  update public.student_assignment_progress
     set completed = least(v_target,coalesce(completed,0)+1),
         last_active = now(),
         updated_at = now(),
         completed_at = case when least(v_target,coalesce(completed,0)+1)>=v_target
                             then coalesce(completed_at,now()) else completed_at end
   where student_id = v_student and assignment_id = p_assignment_id
   returning completed,completed_at into v_completed,v_completed_at;

  if not found then
    insert into public.student_assignment_progress(
      student_id,assignment_id,completed,last_active,updated_at,completed_at
    ) values (
      v_student,p_assignment_id,1,now(),now(),
      case when v_target<=1 then now() else null end
    )
    returning completed,completed_at into v_completed,v_completed_at;
  end if;

  return jsonb_build_object(
    'ok',true,'completed',v_completed,
    'done',v_completed>=v_target,'completed_at',v_completed_at
  );
end;
$function$;


revoke all on function public.record_percent_part_interest_round(uuid,text,text,integer) from public;
grant execute on function public.record_percent_part_interest_round(uuid,text,text,integer) to authenticated;
