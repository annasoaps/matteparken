-- Matteparken: individuella uppdrag och privata lärarmeddelanden.
-- Kör efter tidigare quiz-feedback-skript. Befintliga uppdrag och kottar ändras inte.
create table if not exists public.personal_math_tasks (
 id uuid primary key default gen_random_uuid(),
 class_id uuid not null references public.classes(id) on delete cascade,
 student_id uuid not null references public.students(id) on delete cascade,
 game_id text not null,
 title text not null,
 description text not null default '',
 game_config jsonb not null default '{}'::jsonb,
 target integer not null default 1 check(target between 1 and 20),
 completed integer not null default 0 check(completed between 0 and 20),
 enabled boolean not null default true,
 created_at timestamptz not null default now(),
 completed_at timestamptz
);
create index if not exists personal_math_tasks_student_idx
 on public.personal_math_tasks(student_id, created_at desc);
alter table public.personal_math_tasks enable row level security;
revoke all on public.personal_math_tasks from anon, authenticated;

create table if not exists public.teacher_direct_messages (
 id uuid primary key default gen_random_uuid(),
 class_id uuid not null references public.classes(id) on delete cascade,
 student_id uuid not null references public.students(id) on delete cascade,
 body text not null check(char_length(trim(body)) between 1 and 1200),
 created_at timestamptz not null default now(),
 read_at timestamptz
);
create index if not exists teacher_direct_messages_student_idx
 on public.teacher_direct_messages(student_id, created_at desc);
alter table public.teacher_direct_messages enable row level security;
revoke all on public.teacher_direct_messages from anon, authenticated;

-- Teacher reads only classrooms they own.
create or replace function public.teacher_list_personal_items(p_class_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_tasks jsonb; v_messages jsonb;
begin
 if auth.uid() is null or not public.matteparken_teacher_owns_class(p_class_id) then
  raise exception 'Access denied';
 end if;
 select coalesce(jsonb_agg(jsonb_build_object(
  'id',p.id,'student_id',p.student_id,'game_id',p.game_id,
  'title',p.title,'description',p.description,'game_config',p.game_config,
  'target',p.target,'completed',p.completed,'enabled',p.enabled,
  'created_at',p.created_at,'completed_at',p.completed_at)
  order by p.created_at desc),'[]'::jsonb) into v_tasks
 from public.personal_math_tasks p where p.class_id=p_class_id;
 select coalesce(jsonb_agg(jsonb_build_object(
  'id',m.id,'student_id',m.student_id,'body',m.body,
  'created_at',m.created_at,'read_at',m.read_at)
  order by m.created_at desc),'[]'::jsonb) into v_messages
 from public.teacher_direct_messages m where m.class_id=p_class_id;
 return jsonb_build_object('tasks',v_tasks,'messages',v_messages);
end;
$$;

create or replace function public.teacher_create_personal_task(
 p_student_id uuid,p_game_id text,p_title text,p_game_config jsonb,p_target integer
)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_class uuid; v_id uuid;
begin
 select class_id into v_class from public.students where id=p_student_id and active=true;
 if v_class is null or auth.uid() is null or not public.matteparken_teacher_owns_class(v_class) then
  raise exception 'Access denied';
 end if;
 if p_game_id not in ('multiplication','equations','pow10','fractionDecimal',
  'fractionArithmetic','percentConvert','sharePart','prefixMatch','unitConvert',
  'statistics','scientificNotation') or char_length(trim(coalesce(p_title,''))) not between 1 and 90
  or p_target not between 1 and 20 then
  return jsonb_build_object('ok',false,'reason','invalid_task');
 end if;
 if p_game_config is null or jsonb_typeof(p_game_config) <> 'object' or
  octet_length(p_game_config::text)>2000 then
  return jsonb_build_object('ok',false,'reason','invalid_config');
 end if;
 if p_game_id='multiplication' and p_game_config ? 'table' and
  (p_game_config->>'table') !~ '^([1-9]|10)$' then
  return jsonb_build_object('ok',false,'reason','invalid_table');
 end if;
 insert into public.personal_math_tasks(class_id,student_id,game_id,title,game_config,target)
 values(v_class,p_student_id,p_game_id,trim(p_title),p_game_config,p_target)
 returning id into v_id;
 return jsonb_build_object('ok',true,'id',v_id);
end;
$$;

create or replace function public.teacher_set_personal_task_enabled(p_task_id uuid,p_enabled boolean)
returns boolean language plpgsql security definer set search_path=public as $$
declare v_class uuid;
begin
 select class_id into v_class from public.personal_math_tasks where id=p_task_id;
 if v_class is null or auth.uid() is null or not public.matteparken_teacher_owns_class(v_class) then
  raise exception 'Access denied';
 end if;
 update public.personal_math_tasks set enabled=coalesce(p_enabled,false) where id=p_task_id;
 return found;
end;
$$;

create or replace function public.teacher_delete_personal_task(p_task_id uuid)
returns boolean language plpgsql security definer set search_path=public as $$
declare v_class uuid;
begin
 select class_id into v_class from public.personal_math_tasks where id=p_task_id;
 if v_class is null or auth.uid() is null or not public.matteparken_teacher_owns_class(v_class) then
  raise exception 'Access denied';
 end if;
 delete from public.personal_math_tasks where id=p_task_id;
 return found;
end;
$$;

create or replace function public.teacher_send_direct_message(p_student_id uuid,p_body text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_class uuid; v_id uuid;
begin
 select class_id into v_class from public.students where id=p_student_id and active=true;
 if v_class is null or auth.uid() is null or not public.matteparken_teacher_owns_class(v_class) then
  raise exception 'Access denied';
 end if;
 if char_length(trim(coalesce(p_body,''))) not between 1 and 1200 then
  return jsonb_build_object('ok',false,'reason','invalid_message');
 end if;
 insert into public.teacher_direct_messages(class_id,student_id,body)
 values(v_class,p_student_id,trim(p_body)) returning id into v_id;
 return jsonb_build_object('ok',true,'id',v_id);
end;
$$;

-- Student only receives rows bound to own student_sessions identity.
create or replace function public.student_list_personal_tasks()
returns jsonb language sql security definer set search_path=public as $$
 select coalesce(jsonb_agg(jsonb_build_object(
  'id',p.id,'game_id',p.game_id,'title',p.title,
  'game_config',p.game_config,'target',p.target,'completed',p.completed,
  'created_at',p.created_at,'completed_at',p.completed_at)
  order by p.created_at desc),'[]'::jsonb)
 from public.personal_math_tasks p
 where p.enabled=true and public.matteparken_is_student(p.student_id);
$$;

create or replace function public.student_record_personal_round(
 p_task_id uuid,p_game_id text,p_round_type text,p_table integer default null
)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_task public.personal_math_tasks%rowtype; v_expected text; v_table integer;
begin
 select * into v_task from public.personal_math_tasks
 where id=p_task_id for update;
 if not found or not v_task.enabled or not public.matteparken_is_student(v_task.student_id) then
  return jsonb_build_object('ok',false,'reason','not_available');
 end if;
 v_expected:=case v_task.game_id
  when 'multiplication' then 'table-round'
  when 'equations' then 'solved-random-equation'
  when 'fractionDecimal' then 'matching-board'
  when 'fractionArithmetic' then 'three-calculation-round'
  when 'percentConvert' then 'six-trio-round'
  when 'pow10' then 'ten-question-round'
  when 'sharePart' then 'ten-question-round'
  when 'prefixMatch' then 'ten-question-round'
  when 'unitConvert' then 'ten-question-round'
  when 'statistics' then 'ten-question-round'
  when 'scientificNotation' then 'ten-question-round'
  else null end;
 if p_game_id is distinct from v_task.game_id or p_round_type is distinct from v_expected then
  return jsonb_build_object('ok',false,'reason','wrong_game_or_round');
 end if;
 if v_task.game_id='multiplication' and v_task.game_config ? 'table' then
  v_table:=(v_task.game_config->>'table')::integer;
  if p_table is distinct from v_table then
   return jsonb_build_object('ok',false,'reason','wrong_table');
  end if;
 end if;
 if v_task.completed<v_task.target then
  update public.personal_math_tasks
  set completed=completed+1,
      completed_at=case when completed+1 >= target then now() else null end
  where id=p_task_id
  returning * into v_task;
 end if;
 return jsonb_build_object('ok',true,'completed',v_task.completed,
  'target',v_task.target,'done',v_task.completed>=v_task.target,
  'completed_at',v_task.completed_at);
end;
$$;

create or replace function public.student_list_direct_messages()
returns jsonb language sql security definer set search_path=public as $$
 select coalesce(jsonb_agg(jsonb_build_object(
  'id',m.id,'body',m.body,'created_at',m.created_at,'read_at',m.read_at)
  order by m.created_at desc),'[]'::jsonb)
 from public.teacher_direct_messages m
 where public.matteparken_is_student(m.student_id);
$$;

create or replace function public.student_mark_direct_message_read(p_message_id uuid)
returns boolean language plpgsql security definer set search_path=public as $$
begin
 update public.teacher_direct_messages m set read_at=coalesce(m.read_at,now())
 where m.id=p_message_id and public.matteparken_is_student(m.student_id);
 return found;
end;
$$;

revoke all on function public.teacher_list_personal_items(uuid) from public;
revoke all on function public.teacher_create_personal_task(uuid,text,text,jsonb,integer) from public;
revoke all on function public.teacher_set_personal_task_enabled(uuid,boolean) from public;
revoke all on function public.teacher_send_direct_message(uuid,text) from public;
revoke all on function public.teacher_delete_personal_task(uuid) from public;
revoke all on function public.student_list_personal_tasks() from public;
revoke all on function public.student_record_personal_round(uuid,text,text,integer) from public;
revoke all on function public.student_list_direct_messages() from public;
revoke all on function public.student_mark_direct_message_read(uuid) from public;

grant execute on function public.teacher_list_personal_items(uuid),
 public.teacher_create_personal_task(uuid,text,text,jsonb,integer),
 public.teacher_set_personal_task_enabled(uuid,boolean),
 public.teacher_send_direct_message(uuid,text),
 public.teacher_delete_personal_task(uuid),
 public.student_list_personal_tasks(),
 public.student_record_personal_round(uuid,text,text,integer),
 public.student_list_direct_messages(),
 public.student_mark_direct_message_read(uuid) to authenticated;
