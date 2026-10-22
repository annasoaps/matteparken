-- Kottkampen v1: isolated, server-scored classroom game.
-- Apply via Supabase SQL editor before enabling the feature branch.
-- Existing tables/functions are not changed.
create schema if not exists private;

create table if not exists public.kottkamp_sessions (
 id uuid primary key default gen_random_uuid(),
 class_id uuid not null references public.classes(id),
 teacher_id uuid not null references auth.users(id),
 title text not null,
 games text[] not null,
 mode text not null check(mode in ('time','questions')),
 minutes integer not null default 10 check(minutes between 1 and 60),
 question_count integer not null default 15 check(question_count between 1 and 100),
 status text not null default 'waiting' check(status in ('waiting','running','paused','finished')),
 started_at timestamptz,
 paused_at timestamptz,
 paused_seconds integer not null default 0,
 finished_at timestamptz,
 created_at timestamptz not null default now()
);
create table if not exists public.kottkamp_players (
 session_id uuid not null references public.kottkamp_sessions(id) on delete cascade,
 student_id uuid not null references public.students(id),
 joined_at timestamptz not null default now(),
 score integer not null default 0,
 correct_count integer not null default 0,
 pending_stump boolean not null default false,
 stump_count integer not null default 0,
 stump_outcomes integer[] not null default '{}',
 reward_paid integer,
 primary key(session_id,student_id)
);
create table if not exists public.kottkamp_questions (
 session_id uuid not null references public.kottkamp_sessions(id) on delete cascade,
 question_index integer not null check(question_index between 0 and 1200),
 game_id text not null,
 prompt text not null,
 options text[] not null,
 correct_index integer not null check(correct_index between 0 and 3),
 primary key(session_id,question_index)
);
create table if not exists public.kottkamp_answers (
 session_id uuid not null,
 student_id uuid not null,
 question_index integer not null,
 choice integer not null check(choice between 0 and 3),
 correct boolean not null,
 answered_at timestamptz not null default now(),
 primary key(session_id,student_id,question_index),
 foreign key(session_id,student_id) references public.kottkamp_players(session_id,student_id) on delete cascade
);
alter table public.kottkamp_sessions enable row level security;
alter table public.kottkamp_players enable row level security;
alter table public.kottkamp_questions enable row level security;
alter table public.kottkamp_answers enable row level security;
revoke all on public.kottkamp_sessions,public.kottkamp_players,public.kottkamp_questions,public.kottkamp_answers from anon, authenticated;
-- No public-table policies. All reads/writes go through the authorization-checking RPCs.

create or replace function private.kottkamp_expired(p public.kottkamp_sessions)
returns boolean language sql volatile set search_path='' as $$
 select p.status='running' and p.mode='time' and
 clock_timestamp() >= p.started_at + make_interval(secs=>p.minutes*60+p.paused_seconds)
$$;

create or replace function private.kottkamp_finish_impl(p_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare v public.kottkamp_sessions; p record; amount integer;
begin
 select * into v from public.kottkamp_sessions where id=p_id for update;
 if v.id is null or v.status='finished' then return; end if;
 update public.kottkamp_sessions set status='finished',finished_at=clock_timestamp(),paused_at=null where id=p_id;
 for p in
  select student_id,score,correct_count,
   rank() over(order by score desc,correct_count desc) as position,
   (select count(*) from public.kottkamp_answers a where a.session_id=p_id and a.student_id=x.student_id) as answers
  from public.kottkamp_players x where x.session_id=p_id
 loop
  amount:=case when p.answers=0 then 0 when p.position=1 then 25 when p.position=2 then 20 when p.position=3 then 15 else 8 end;
  update public.kottkamp_players set reward_paid=amount,pending_stump=false,stump_outcomes='{}' where session_id=p_id and student_id=p.student_id and reward_paid is null;
  if found and amount>0 then
   perform public.matteparken_ensure_cones(p.student_id);
   update public.student_cones set balance=balance+amount,updated_at=now() where student_id=p.student_id;
  end if;
 end loop;
end $$;

-- Generates an answer key privately. Students only receive shuffled options without correct_index.
create or replace function private.kottkamp_question_for(p_session uuid,p_index integer)
returns public.kottkamp_questions language plpgsql security definer set search_path='' as $$
declare s public.kottkamp_sessions; q public.kottkamp_questions;
 g text; prompt_text text; result_value numeric; a integer; b integer; percent integer;
 before_value integer; after_value integer; delta numeric; correct_text text;
 opts text[]; answer_at integer; wrong numeric;
begin
 select * into q from public.kottkamp_questions where session_id=p_session and question_index=p_index;
 if found then return q; end if;
 select * into s from public.kottkamp_sessions where id=p_session;
 if s.id is null or p_index<0 or p_index>1200 then raise exception 'invalid_question'; end if;
 g:=s.games[(p_index % array_length(s.games,1))+1];
 a:=10+(floor(random()*16)::int)*10;
 b:=2+floor(random()*10)::int;
 percent:=(array[5,10,15,20,25,30,40,50,60,75])[1+floor(random()*10)::int];
 case g
 when 'percentConvert' then
  if random()<0.5 then
   prompt_text:=percent||' % = ? i decimalform';
   result_value:=percent::numeric/100;
  else
   prompt_text:=replace(trim(trailing '.' from to_char(percent::numeric/100,'FM999999990.9999')),'.',',')||' = ? %';
   result_value:=percent;
  end if;
 when 'sharePart' then
  before_value:=100;
  prompt_text:='Av 100 rutor är '||percent||' färgade. Hur stor andel är färgad (i %)?';
  result_value:=percent;
 when 'percentChange' then
  before_value:=a*2;
  after_value:=before_value*(100+percent)/100;
  if random()<0.5 then
   after_value:=before_value*(100-percent)/100;
  end if;
  prompt_text:='Antalet ändras från '||before_value||' till '||after_value||'. Hur stor är den procentuella '||
   (case when after_value>before_value then 'ökningen' else 'minskningen' end)||'? (Svara i %)';
  result_value:=percent;
 when 'percentPart' then
  prompt_text:='Hur mycket är '||percent||' % av '||a*10||'?';
  result_value:=percent*a/10.0;
 when 'whole' then
  before_value:=a*10;
  after_value:=before_value*percent/100;
  prompt_text:=percent||' % av ett tal är '||after_value||'. Vilket är hela talet?';
  result_value:=before_value;
 when 'fractionDecimal' then
  prompt_text:='Vad är '||b||'/10 i decimalform?';
  result_value:=b/10.0;
 when 'multiplication' then
  prompt_text:=b||' × '||(a/10)||' = ?';
  result_value:=b*(a/10);
 when 'equations' then
  prompt_text:='Lös ekvationen: '||b||'x + '||a||' = '||(b*(a/10)+a)||'. Vad är x?';
  result_value:=a/10;
 when 'pow10' then
  prompt_text:='Vad är '||a||' ÷ 10?';
  result_value:=a/10.0;
 when 'interest' then
  prompt_text:='Hur stor är årsräntan i kronor på '||a*10||' kr om räntesatsen är '||percent||' %?';
  result_value:=a*percent/10.0;
 when 'unitConvert' then
  prompt_text:='Hur många centimeter är '||b||' meter?';
  result_value:=b*100;
 when 'prefixMatch' then
  prompt_text:='Hur många millimeter är '||b||' centimeter?';
  result_value:=b*10;
 when 'statistics' then
  prompt_text:='Vad är medelvärdet av '||b||', '||(b+4)||' och '||(b+8)||'?';
  result_value:=b+4;
 when 'fractionArithmetic' then
  prompt_text:='Vad är 1/2 + '||b||'/10 i decimalform?';
  result_value:=0.5+b/10.0;
 when 'scientificNotation' then
  prompt_text:='Vad är '||b||' × 10² som vanligt tal?';
  result_value:=b*100;
 else raise exception 'unsupported_game: %',g;
 end case;
 delta:=case when abs(result_value)<2 then 0.1 when abs(result_value)<20 then 1 else 10 end;
 correct_text:=replace(trim(trailing '.' from to_char(round(result_value,4),'FM999999990.9999')),'.',',');
 opts:=array[
  correct_text,
  replace(trim(trailing '.' from to_char(round(result_value+delta,4),'FM999999990.9999')),'.',','),
  replace(trim(trailing '.' from to_char(round(result_value-delta,4),'FM999999990.9999')),'.',','),
  replace(trim(trailing '.' from to_char(round(result_value+2*delta,4),'FM999999990.9999')),'.',',')
 ];
 answer_at:=floor(random()*4)::int;
 -- move answer from first position to its randomly chosen position
 opts[1]:=opts[answer_at+1];
 opts[answer_at+1]:=correct_text;
 insert into public.kottkamp_questions(session_id,question_index,game_id,prompt,options,correct_index)
 values (p_session,p_index,g,prompt_text,opts,answer_at)
 on conflict (session_id,question_index) do nothing;
 select * into q from public.kottkamp_questions where session_id=p_session and question_index=p_index;
 return q;
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
  'score',pl.score,'correct',pl.correct_count,'answered',(select count(*) from public.kottkamp_answers a where a.session_id=p_id and a.student_id=pl.student_id),
  'reward',pl.reward_paid) order by pl.score desc,pl.correct_count desc),'[]'::jsonb)
 into data from public.kottkamp_players pl join public.students st on st.id=pl.student_id where pl.session_id=p_id;
 return jsonb_build_object('ok',true,'session',jsonb_build_object('id',s.id,'title',s.title,
  'status',s.status,'mode',s.mode,'minutes',s.minutes,'question_count',s.question_count,
  'started_at',s.started_at,'paused_seconds',s.paused_seconds,'paused_at',s.paused_at,
  'finished_at',s.finished_at,'games',s.games),'players',data,'server_now',clock_timestamp());
end $$;

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
 if p_action='join' then
  if s.status='finished' then return jsonb_build_object('ok',false,'reason','already_finished'); end if;
  insert into public.kottkamp_players(session_id,student_id) values(p_id,sid) on conflict do nothing;
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
  update public.kottkamp_players set score=score+(case when is_correct then 100 else 0 end),
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
  return jsonb_build_object('ok',true,'correct',is_correct,'correct_answer',q.options[q.correct_index+1],
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
   'score',p.score,'correct',p.correct_count) order by p.score desc,p.correct_count desc),'[]'::jsonb)
 into data from public.kottkamp_players p join public.students st on st.id=p.student_id where p.session_id=p_id;
 return jsonb_build_object('ok',true,'session',jsonb_build_object('id',s.id,'title',s.title,
   'status',s.status,'mode',s.mode,'minutes',s.minutes,'question_count',s.question_count,
   'started_at',s.started_at,'paused_at',s.paused_at,'paused_seconds',s.paused_seconds),
   'me',jsonb_build_object('score',pl.score,'correct',pl.correct_count,'answered',n,'pending_stump',pl.pending_stump,
    'reward',pl.reward_paid),'players',data,'server_now',clock_timestamp());
end $$;

create or replace function public.kottkamp_teacher(p_action text,p_session_id uuid default null,p_payload jsonb default '{}'::jsonb)
returns jsonb language sql security definer set search_path='' as $$
 select private.kottkamp_teacher_impl(p_action,p_session_id,p_payload)
$$;
create or replace function public.kottkamp_student(p_action text,p_session_id uuid default null,p_payload jsonb default '{}'::jsonb)
returns jsonb language sql security definer set search_path='' as $$
 select private.kottkamp_student_impl(p_action,p_session_id,p_payload)
$$;
revoke all on function public.kottkamp_teacher(text,uuid,jsonb),public.kottkamp_student(text,uuid,jsonb) from public,anon;
grant execute on function public.kottkamp_teacher(text,uuid,jsonb),public.kottkamp_student(text,uuid,jsonb) to authenticated;
revoke all on function private.kottkamp_teacher_impl(text,uuid,jsonb),private.kottkamp_student_impl(text,uuid,jsonb),private.kottkamp_finish_impl(uuid),private.kottkamp_question_for(uuid,integer),private.kottkamp_expired(public.kottkamp_sessions) from public,anon,authenticated;
