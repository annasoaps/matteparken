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
  'reward',pl.reward_paid,
  'prizes_total',(select count(*) from public.kottkamp_prizes pr where pr.session_id=p_id and pr.student_id=pl.student_id),
  'prizes_confirmed',(select count(*) from public.kottkamp_prizes pr where pr.session_id=p_id and pr.student_id=pl.student_id and pr.confirmed_at is not null)) order by pl.score desc,pl.correct_count desc),'[]'::jsonb)
 into data from public.kottkamp_players pl join public.students st on st.id=pl.student_id where pl.session_id=p_id;
 return jsonb_build_object('ok',true,'session',jsonb_build_object('id',s.id,'title',s.title,
  'status',s.status,'mode',s.mode,'minutes',s.minutes,'question_count',s.question_count,
  'started_at',s.started_at,'paused_seconds',s.paused_seconds,'paused_at',s.paused_at,
  'finished_at',s.finished_at,'games',s.games),'players',data,'server_now',clock_timestamp());
end $$;

