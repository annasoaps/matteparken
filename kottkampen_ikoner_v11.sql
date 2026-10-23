-- Kottkampen 1.1 step 2: a student reserves one unique icon per contest.
alter table public.kottkamp_players add column if not exists icon_id integer;
create unique index if not exists kottkamp_unique_icon
 on public.kottkamp_players(session_id,icon_id) where icon_id is not null;
do $constraint$ begin
 if not exists(select 1 from pg_constraint where conname='kottkamp_valid_icon') then
  alter table public.kottkamp_players add constraint kottkamp_valid_icon
   check(icon_id between 1 and 30);
 end if;
end $constraint$;
create or replace function private.kottkamp_student_impl(p_action text,p_id uuid,p_data jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare sid uuid; cid uuid; s public.kottkamp_sessions; pl public.kottkamp_players; q public.kottkamp_questions;
 n integer; ch integer; is_correct boolean; data jsonb; outcomes integer[]; j integer; slot integer; award integer;
begin
 select st.id, st.class_id into sid,cid
 from public.student_sessions ss join public.students st on st.id=ss.student_id
 where ss.auth_user_id=auth.uid() and st.active=true limit 1;
 if sid is null then return jsonb_build_object('ok',false,'reason','student_login_required'); end if;
 if p_action='list' then
  return jsonb_build_object('ok',true,'sessions',coalesce((
   select jsonb_agg(jsonb_build_object('id',id,'title',title,'status',status,'mode',mode,'minutes',minutes))
   from (select * from public.kottkamp_sessions where class_id=cid and (status<>'finished' or finished_at>now()-interval '1 day')
    order by created_at desc limit 8) x
  ),'[]'::jsonb));
 end if;
 select * into s from public.kottkamp_sessions where id=p_id and class_id=cid for update;
 if s.id is null then return jsonb_build_object('ok',false,'reason','wrong_class'); end if;
 if private.kottkamp_expired(s) then
  perform private.kottkamp_finish_impl(p_id);
  select * into s from public.kottkamp_sessions where id=p_id;
 end if;
 if p_action='icons' then
  return jsonb_build_object('ok',true,'taken',coalesce(
    (select jsonb_agg(icon_id) from public.kottkamp_players
     where session_id=p_id and icon_id is not null),'[]'::jsonb),
    'mine',(select icon_id from public.kottkamp_players where session_id=p_id and student_id=sid));
 end if;
 if p_action='join' then
  if s.status='finished' then return jsonb_build_object('ok',false,'reason','already_finished'); end if;
  if coalesce((p_data->>'icon')::int,0) not between 1 and 30 then
   return jsonb_build_object('ok',false,'reason','icon_required');
  end if;
  begin
   insert into public.kottkamp_players(session_id,student_id,icon_id)
   values(p_id,sid,(p_data->>'icon')::int)
   on conflict (session_id,student_id) do nothing;
   update public.kottkamp_players set icon_id=(p_data->>'icon')::int
   where session_id=p_id and student_id=sid and icon_id is null;
  exception when unique_violation then
   return jsonb_build_object('ok',false,'reason','icon_taken');
  end;
 end if;
 select * into pl from public.kottkamp_players where session_id=p_id and student_id=sid for update;
 if pl.student_id is null then return jsonb_build_object('ok',false,'reason','join_first'); end if;
 select count(*) into n from public.kottkamp_answers where session_id=p_id and student_id=sid;
 if p_action='question' then
  if s.status<>'running' then return jsonb_build_object('ok',true,'status',s.status); end if;
  if pl.pending_stump then return jsonb_build_object('ok',true,'status','stump'); end if;
  if s.mode='questions' and n>=s.question_count then return jsonb_build_object('ok',true,'status','complete'); end if;
  q:=private.kottkamp_question_for(p_id,n);
  return jsonb_build_object('ok',true,'status','question','index',n,'game_id',q.game_id,'prompt',q.prompt,
    'options',q.options,'score',pl.score,'correct',pl.correct_count);
 elsif p_action='answer' then
  if s.status<>'running' or pl.pending_stump or (s.mode='questions' and n>=s.question_count)
   then return jsonb_build_object('ok',false,'reason','not_answerable'); end if;
  if coalesce((p_data->>'index')::int,-1)<>n then return jsonb_build_object('ok',false,'reason','wrong_question'); end if;
  ch:=(p_data->>'choice')::int;
  if ch not between 0 and 3 then return jsonb_build_object('ok',false,'reason','invalid_choice'); end if;
  q:=private.kottkamp_question_for(p_id,n);
  is_correct:=ch=q.correct_index;
  insert into public.kottkamp_answers(session_id,student_id,question_index,choice,correct)
    values(p_id,sid,n,ch,is_correct);
  update public.kottkamp_players set score=score+(case when is_correct then 100 else -50 end),
    correct_count=correct_count+(case when is_correct then 1 else 0 end),
    pending_stump=(is_correct and mod(correct_count+1,3)=0)
    where session_id=p_id and student_id=sid returning * into pl;
  if pl.pending_stump then
   -- shuffle the three outcomes. They affect competition score ONLY.
   outcomes:=array[0,80,-40];
   for j in reverse 3..2 loop
    slot:=1+floor(random()*j)::int;
    award:=outcomes[j];outcomes[j]:=outcomes[slot];outcomes[slot]:=award;
   end loop;
   update public.kottkamp_players set stump_outcomes=outcomes where session_id=p_id and student_id=sid;
  end if;
  return jsonb_build_object('ok',true,'correct',is_correct,'delta',(case when is_correct then 100 else -50 end),'correct_answer',q.options[q.correct_index+1],
    'score',pl.score,'stump',pl.pending_stump);
 elsif p_action='stump' then
  if s.status<>'running' or not pl.pending_stump then return jsonb_build_object('ok',false,'reason','no_stump'); end if;
  slot:=(p_data->>'slot')::int;
  if slot not between 1 and 3 then return jsonb_build_object('ok',false,'reason','invalid_stump'); end if;
  award:=pl.stump_outcomes[slot];
  update public.kottkamp_players
   set score=greatest(0,score+award),pending_stump=false,stump_count=stump_count+1,stump_outcomes='{}'
   where session_id=p_id and student_id=sid returning * into pl;
  return jsonb_build_object('ok',true,'award',award,'score',pl.score);
 end if;
 select coalesce(jsonb_agg(jsonb_build_object('name','Ekorre '||coalesce(st.list_number::text,'?'),
   'score',p.score,'correct',p.correct_count,'icon_id',p.icon_id) order by p.score desc,p.correct_count desc),'[]'::jsonb)
 into data from public.kottkamp_players p join public.students st on st.id=p.student_id where p.session_id=p_id;
 return jsonb_build_object('ok',true,'session',jsonb_build_object('id',s.id,'title',s.title,
   'status',s.status,'mode',s.mode,'minutes',s.minutes,'question_count',s.question_count,
   'started_at',s.started_at,'paused_at',s.paused_at,'paused_seconds',s.paused_seconds),
   'me',jsonb_build_object('score',pl.score,'correct',pl.correct_count,'answered',n,'pending_stump',pl.pending_stump,
    'reward',pl.reward_paid,'icon_id',pl.icon_id),'players',data,'server_now',clock_timestamp());
end $$;




create or replace function private.kottkamp_teacher_impl(p_action text,p_id uuid,p_data jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare s public.kottkamp_sessions; v_class uuid; games text[]; requested_games text[];
 data jsonb; v_title text; v_mode text; v_count integer; v_minutes integer;
begin
 if auth.uid() is null then return jsonb_build_object('ok',false,'reason','not_logged_in'); end if;
 if p_action='list' then
  return jsonb_build_object('ok',true,'sessions',coalesce((
   select jsonb_agg(jsonb_build_object('id',id,'title',title,'status',status,'created_at',created_at) order by created_at desc)
   from (select k.* from public.kottkamp_sessions k join public.teacher_classes tc on tc.class_id=k.class_id
         where tc.teacher_id=auth.uid() order by k.created_at desc limit 25) x
  ),'[]'::jsonb));
 end if;
 if p_action='create' then
  v_class:=(p_data->>'class_id')::uuid;
  if not exists(select 1 from public.teacher_classes where teacher_id=auth.uid() and class_id=v_class)
   then return jsonb_build_object('ok',false,'reason','not_your_class'); end if;
  select coalesce(array_agg(value), '{}'::text[]) into requested_games
    from jsonb_array_elements_text(coalesce(p_data->'games','[]'::jsonb));
  select array_agg(distinct g) into games from unnest(requested_games) g
   where g=any(array['percentConvert','sharePart','percentChange','percentPart','whole','fractionDecimal','multiplication','equations','pow10','interest','unitConvert','prefixMatch','statistics','fractionArithmetic','scientificNotation']);
  if coalesce(array_length(games,1),0)=0 or coalesce(array_length(games,1),0)>15
   then return jsonb_build_object('ok',false,'reason','choose_games'); end if;
  v_mode:=p_data->>'mode';
  if v_mode not in ('time','questions') then return jsonb_build_object('ok',false,'reason','invalid_mode'); end if;
  v_count:=coalesce((p_data->>'question_count')::int,15);
  v_minutes:=coalesce((p_data->>'minutes')::int,10);
  if v_count not between 1 and 100 or v_minutes not between 1 and 60 then return jsonb_build_object('ok',false,'reason','invalid_limit'); end if;
  v_title:=left(trim(coalesce(p_data->>'title','Kottjakten')),90);
  if v_title='' then v_title:='Kottjakten'; end if;
  insert into public.kottkamp_sessions(class_id,teacher_id,title,games,mode,question_count,minutes)
    values(v_class,auth.uid(),v_title,games,v_mode,v_count,v_minutes)
    returning * into s;
  return jsonb_build_object('ok',true,'id',s.id);
 end if;
 select * into s from public.kottkamp_sessions where id=p_id for update;
 if s.id is null or not exists(select 1 from public.teacher_classes where class_id=s.class_id and teacher_id=auth.uid())
  then return jsonb_build_object('ok',false,'reason','not_your_session'); end if;
 if private.kottkamp_expired(s) then perform private.kottkamp_finish_impl(p_id); select * into s from public.kottkamp_sessions where id=p_id; end if;
 if p_action='start' and s.status='waiting' then
  update public.kottkamp_sessions set status='running',started_at=clock_timestamp(),paused_seconds=0 where id=p_id;
 elsif p_action='pause' and s.status='running' and s.mode='time' then
  update public.kottkamp_sessions set status='paused',paused_at=clock_timestamp() where id=p_id;
 elsif p_action='resume' and s.status='paused' then
  update public.kottkamp_sessions set status='running',
    paused_seconds=paused_seconds+greatest(0,extract(epoch from clock_timestamp()-paused_at)::int),paused_at=null where id=p_id;
 elsif p_action='finish' then
  perform private.kottkamp_finish_impl(p_id);
 end if;
 select * into s from public.kottkamp_sessions where id=p_id;
 select coalesce(jsonb_agg(jsonb_build_object('name','Ekorre '||coalesce(st.list_number::text,'?'),
  'score',pl.score,'correct',pl.correct_count,'icon_id',pl.icon_id,'answered',(select count(*) from public.kottkamp_answers a where a.session_id=p_id and a.student_id=pl.student_id),
  'reward',pl.reward_paid) order by pl.score desc,pl.correct_count desc),'[]'::jsonb)
 into data from public.kottkamp_players pl join public.students st on st.id=pl.student_id where pl.session_id=p_id;
 return jsonb_build_object('ok',true,'session',jsonb_build_object('id',s.id,'title',s.title,
  'status',s.status,'mode',s.mode,'minutes',s.minutes,'question_count',s.question_count,
  'started_at',s.started_at,'paused_seconds',s.paused_seconds,'paused_at',s.paused_at,
  'finished_at',s.finished_at,'games',s.games),'players',data,'server_now',clock_timestamp());
end $$;

