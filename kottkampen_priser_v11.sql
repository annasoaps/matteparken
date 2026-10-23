-- Kottkampen v1.1 / belöningsnivåer. Endast servern kan lägga till tävlingspriser.
create table if not exists public.kottkamp_prizes(
 id uuid primary key default gen_random_uuid(),
 session_id uuid not null,
 student_id uuid not null,
 prize_key text not null,
 prize_type text not null check(prize_type in ('seedPack','decorBox','blindBag')),
 created_at timestamptz not null default clock_timestamp(),
 unique(session_id,student_id,prize_key),
 foreign key(session_id,student_id) references public.kottkamp_players(session_id,student_id) on delete cascade
);
alter table public.kottkamp_prizes enable row level security;
revoke all on public.kottkamp_prizes from anon,authenticated;
create or replace function private.kottkamp_finish_impl(p_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare v public.kottkamp_sessions; p record; amount integer; v_paid boolean;
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
  v_paid:=found;
  if v_paid and p.answers>0 then
   if p.score>1000 then
    insert into public.kottkamp_prizes(session_id,student_id,prize_key,prize_type)
     values(p_id,p.student_id,'score-threshold','decorBox') on conflict do nothing;
   elsif p.score>500 then
    insert into public.kottkamp_prizes(session_id,student_id,prize_key,prize_type)
     values(p_id,p.student_id,'score-threshold','seedPack') on conflict do nothing;
   end if;
  end if;
  if v_paid and amount>0 then
   perform public.matteparken_ensure_cones(p.student_id);
   update public.student_cones set balance=balance+amount,updated_at=now() where student_id=p.student_id;
  end if;
 end loop;
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
 if p_action='prizes' then
  return jsonb_build_object('ok',true,'prizes',coalesce(
   (select jsonb_agg(jsonb_build_object('id',id,'type',prize_type,'source',prize_key) order by created_at)
    from public.kottkamp_prizes where session_id=p_id and student_id=sid),'[]'::jsonb));
 end if;
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





