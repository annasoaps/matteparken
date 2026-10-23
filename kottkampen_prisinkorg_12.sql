-- Kottkampen 1.2: durable student prize inbox and audit acknowledgements.
-- Preserves all historic prizes and score results; new threshold applies to future finishes.
alter table public.kottkamp_prizes add column if not exists confirmed_at timestamptz;
alter table public.kottkamp_prizes add column if not exists last_delivery_attempt_at timestamptz;
-- No SELECT/INSERT/UPDATE access granted on the prize table to browser roles.
-- Only securely scoped RPC functions may read or acknowledge an individual student's prizes.

create or replace function private.kottkamp_inbox_impl(p_action text,p_prize_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $inbox$
declare v_sid uuid; v_result jsonb; v_found boolean;
begin
 select st.id into v_sid from public.student_sessions ss join public.students st on st.id=ss.student_id
  where ss.auth_user_id=auth.uid() and st.active=true limit 1;
 if v_sid is null then return jsonb_build_object('ok',false,'reason','student_login_required'); end if;
 if p_action='confirm' then
  if p_prize_id is null then return jsonb_build_object('ok',false,'reason','missing_prize'); end if;
  update public.kottkamp_prizes
   set confirmed_at=coalesce(confirmed_at,clock_timestamp()),last_delivery_attempt_at=clock_timestamp()
   where id=p_prize_id and student_id=v_sid;
  v_found:=found;
  if not v_found then return jsonb_build_object('ok',false,'reason','unknown_prize'); end if;
  return jsonb_build_object('ok',true,'confirmed',true);
 elsif p_action<>'list' then
  return jsonb_build_object('ok',false,'reason','invalid_action');
 end if;
 select coalesce(jsonb_agg(jsonb_build_object(
  'id',pr.id,'type',pr.prize_type,'item',pr.prize_item,
  'source',pr.prize_key,'title',s.title,'created_at',pr.created_at,
  'confirmed_at',pr.confirmed_at
 ) order by pr.created_at,pr.id),'[]'::jsonb) into v_result
 from public.kottkamp_prizes pr join public.kottkamp_sessions s on s.id=pr.session_id
 where pr.student_id=v_sid;
 return jsonb_build_object('ok',true,'prizes',v_result);
end $inbox$;

create or replace function public.kottkamp_prize_inbox(p_action text default 'list',p_prize_id uuid default null)
returns jsonb language sql security definer set search_path='' as $wrapper$
 select private.kottkamp_inbox_impl(p_action,p_prize_id);
$wrapper$;
revoke all on function private.kottkamp_inbox_impl(text,uuid) from public,anon,authenticated;
revoke all on function public.kottkamp_prize_inbox(text,uuid) from public,anon;
grant execute on function public.kottkamp_prize_inbox(text,uuid) to authenticated;

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
   -- Rules from 1.2: two cumulative blind bags at 800 and 1500 points.
   if p.score>=800 then
    insert into public.kottkamp_prizes(session_id,student_id,prize_key,prize_type)
     values(p_id,p.student_id,'score-800','blindBag') on conflict do nothing;
   end if;
   if p.score>=1500 then
    insert into public.kottkamp_prizes(session_id,student_id,prize_key,prize_type)
     values(p_id,p.student_id,'score-1500','blindBag') on conflict do nothing;
   end if;
  end if;
  if v_paid and amount>0 then
   perform public.matteparken_ensure_cones(p.student_id);
   update public.student_cones set balance=balance+amount,updated_at=now() where student_id=p.student_id;
  end if;
 end loop;
end $$;


