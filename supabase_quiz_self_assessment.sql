-- Matteparken: Min mattevecka, extra del efter läxförhöret.
-- Kräver att supabase_quiz_feedback.sql redan har körts.
-- Påverkar inte quiz_attempts, elevkoder, kottar eller gamla elevsvar.

alter table public.quiz_reviews
  add column if not exists self_assessment jsonb;

-- Varje elev får bara spara självskattning för sitt eget genomförda förhör.
create or replace function public.student_save_quiz_self_assessment(
  p_quiz_id uuid, p_assessment jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_student_id uuid;
  v_confidence text;
  v_effort text;
  v_tip text;
begin
  if p_assessment is null or jsonb_typeof(p_assessment) is distinct from 'object' then
    return jsonb_build_object('ok', false, 'reason', 'invalid_format');
  end if;
  if octet_length(p_assessment::text) > 4000 then
    return jsonb_build_object('ok', false, 'reason', 'too_long');
  end if;
  if jsonb_typeof(p_assessment->'confidence') is distinct from 'string'
    or jsonb_typeof(p_assessment->'effort') is distinct from 'string'
    or jsonb_typeof(p_assessment->'tip') is distinct from 'string'
    or jsonb_typeof(p_assessment->'factors') is distinct from 'array' then
    return jsonb_build_object('ok', false, 'reason', 'invalid_format');
  end if;

  v_confidence := p_assessment->>'confidence';
  v_effort := p_assessment->>'effort';
  v_tip := trim(p_assessment->>'tip');
  if v_confidence not in ('more_practice','unsure','quite_sure','very_sure')
    or v_effort not in ('not_satisfied','quite_satisfied','satisfied','very_satisfied')
    or char_length(v_tip) < 1 or char_length(v_tip) > 300
    or jsonb_array_length(p_assessment->'factors') < 1
    or jsonb_array_length(p_assessment->'factors') > 11 then
    return jsonb_build_object('ok', false, 'reason', 'invalid_answers');
  end if;
  if exists (
    select 1
    from jsonb_array_elements(p_assessment->'factors') as item(value)
    where jsonb_typeof(item.value) is distinct from 'string'
      or item.value #>> '{}' not in (
        'understood','focus','friend','teacher','peace','sleep',
        'food','distracted','noise','computer','difficulty'
      )
  ) then
    return jsonb_build_object('ok', false, 'reason', 'invalid_factors');
  end if;

  select a.student_id into v_student_id
  from public.quiz_attempts a
  where a.quiz_id = p_quiz_id
    and a.completed_at is not null
    and public.matteparken_is_student(a.student_id)
  limit 1;

  if v_student_id is null then
    return jsonb_build_object('ok', false, 'reason', 'no_completed_attempt');
  end if;

  insert into public.quiz_reviews(quiz_id, student_id, answers, self_assessment)
  values(p_quiz_id, v_student_id, '[]'::jsonb, p_assessment)
  on conflict (quiz_id, student_id) do update
    set self_assessment = coalesce(public.quiz_reviews.self_assessment, excluded.self_assessment);

  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function public.student_save_quiz_self_assessment(uuid,jsonb) from public;
grant execute on function public.student_save_quiz_self_assessment(uuid,jsonb) to authenticated;

-- Uppdaterar lärarens befintliga läsning så att självskattningen kommer med.
create or replace function public.teacher_list_quiz_reviews(p_class_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_data jsonb;
begin
  if not public.matteparken_teacher_owns_class(p_class_id) then
    raise exception 'Access denied';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'quiz_id', r.quiz_id,
    'student_id', r.student_id,
    'answers', r.answers,
    'self_assessment', r.self_assessment,
    'teacher_feedback', r.teacher_feedback,
    'feedback_at', r.feedback_at,
    'feedback_read_at', r.feedback_read_at
  )), '[]'::jsonb)
  into v_data
  from public.quiz_reviews r
  join public.quizzes q on q.id = r.quiz_id
  where q.class_id = p_class_id;
  return v_data;
end;
$$;
revoke all on function public.teacher_list_quiz_reviews(uuid) from public;
grant execute on function public.teacher_list_quiz_reviews(uuid) to authenticated;
