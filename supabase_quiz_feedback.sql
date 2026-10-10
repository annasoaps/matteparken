-- Matteparken: detaljerade läxförhör och läraråterkoppling (v1)
-- Kör en gång i Supabase SQL Editor efter att koden har granskats.
-- Elevsvar skyddas bakom SECURITY DEFINER-funktioner, inte öppna tabellrättigheter.
create table if not exists public.quiz_reviews (
 quiz_id uuid not null references public.quizzes(id) on delete cascade,
 student_id uuid not null references public.students(id) on delete cascade,
 answers jsonb not null default '[]'::jsonb,
 teacher_feedback text,
 feedback_at timestamptz,
 feedback_read_at timestamptz,
 created_at timestamptz not null default now(),
 primary key (quiz_id,student_id)
);
alter table public.quiz_reviews enable row level security;
revoke all on public.quiz_reviews from anon,authenticated;
-- Elevens anonyma Supabase-inloggning kopplas via student_sessions.
create or replace function public.matteparken_is_student(p_student_id uuid)
returns boolean language sql security definer set search_path=public as $$
 select auth.uid() is not null and exists (
  select 1 from public.student_sessions ss
  where ss.student_id=p_student_id and ss.auth_user_id=auth.uid()
 );
$$;
revoke all on function public.matteparken_is_student(uuid) from public;
grant execute on function public.matteparken_is_student(uuid) to authenticated;

create or replace function public.student_save_quiz_review(p_quiz_id uuid,p_answers jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_student uuid; v_id uuid;
begin
 if jsonb_typeof(p_answers) <> 'array' or jsonb_array_length(p_answers)>30
    or octet_length(p_answers::text)>50000 then
   return jsonb_build_object('ok',false,'reason','invalid_answers');
 end if;
 select qa.student_id into v_student
 from public.quiz_attempts qa where qa.quiz_id=p_quiz_id
 and public.matteparken_is_student(qa.student_id)
 and qa.completed_at is not null limit 1;
 if v_student is null then return jsonb_build_object('ok',false,'reason','no_completed_attempt'); end if;
 insert into public.quiz_reviews(quiz_id,student_id,answers)
 values(p_quiz_id,v_student,p_answers) on conflict(quiz_id,student_id) do nothing;
 return jsonb_build_object('ok',true);
end;
$$;

create or replace function public.teacher_list_quiz_reviews(p_class_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_data jsonb;
begin
 if not public.matteparken_teacher_owns_class(p_class_id) then
  raise exception 'Access denied';
 end if;
 select coalesce(jsonb_agg(jsonb_build_object(
 'quiz_id',r.quiz_id,'student_id',r.student_id,'answers',r.answers,
 'teacher_feedback',r.teacher_feedback,'feedback_at',r.feedback_at,
 'feedback_read_at',r.feedback_read_at)),'[]'::jsonb)
 into v_data from public.quiz_reviews r join public.quizzes q on q.id=r.quiz_id
 where q.class_id=p_class_id;
 return v_data;
end;
$$;

create or replace function public.teacher_send_quiz_feedback(
 p_quiz_id uuid,p_student_id uuid,p_feedback text)
returns jsonb language plpgsql security definer set search_path=public as $$
begin
 if not exists(select 1 from public.quizzes q join public.students s on s.class_id=q.class_id
 where q.id=p_quiz_id and s.id=p_student_id and public.matteparken_teacher_owns_class(q.class_id)) then
  raise exception 'Access denied';
 end if;
 if length(trim(coalesce(p_feedback,'')))>1500 then
  return jsonb_build_object('ok',false,'reason','too_long');
 end if;
 if not exists(select 1 from public.quiz_attempts
 where quiz_id=p_quiz_id and student_id=p_student_id and completed_at is not null) then
  return jsonb_build_object('ok',false,'reason','not_completed');
 end if;
 insert into public.quiz_reviews(quiz_id,student_id,answers,teacher_feedback,feedback_at,feedback_read_at)
 values(p_quiz_id,p_student_id,'[]'::jsonb,nullif(trim(p_feedback),''),now(),null)
 on conflict(quiz_id,student_id) do update set
 teacher_feedback=excluded.teacher_feedback,feedback_at=excluded.feedback_at,feedback_read_at=null;
 return jsonb_build_object('ok',true);
end;
$$;

create or replace function public.student_list_quiz_feedback()
returns jsonb language sql security definer set search_path=public as $$
 select coalesce(jsonb_agg(jsonb_build_object(
  'quiz_id',r.quiz_id,'title',q.title,'teacher_feedback',r.teacher_feedback,
  'feedback_at',r.feedback_at,'feedback_read_at',r.feedback_read_at,
  'answers',r.answers) order by r.feedback_at desc),'[]'::jsonb)
 from public.quiz_reviews r join public.quizzes q on q.id=r.quiz_id
 where public.matteparken_is_student(r.student_id) and r.teacher_feedback is not null;
$$;

create or replace function public.student_mark_quiz_feedback_read(p_quiz_id uuid)
returns boolean language plpgsql security definer set search_path=public as $$
begin
 update public.quiz_reviews set feedback_read_at=coalesce(feedback_read_at,now())
 where quiz_id=p_quiz_id and public.matteparken_is_student(student_id)
 and teacher_feedback is not null;
 return found;
end;
$$;
revoke all on function public.student_save_quiz_review(uuid,jsonb) from public;
revoke all on function public.teacher_list_quiz_reviews(uuid) from public;
revoke all on function public.teacher_send_quiz_feedback(uuid,uuid,text) from public;
revoke all on function public.student_list_quiz_feedback() from public;
revoke all on function public.student_mark_quiz_feedback_read(uuid) from public;
grant execute on function public.student_save_quiz_review(uuid,jsonb),
 public.teacher_list_quiz_reviews(uuid),
 public.teacher_send_quiz_feedback(uuid,uuid,text),
 public.student_list_quiz_feedback(),
 public.student_mark_quiz_feedback_read(uuid) to authenticated;
