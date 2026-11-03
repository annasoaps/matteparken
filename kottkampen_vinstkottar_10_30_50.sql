-- Kottkampen: integer tens for contest finishing rewards.
-- Winner: 50; runner-up: 30; all other active participants: 10; no answers: 0.
-- Completed sessions remain unchanged because the finish RPC exits for finished rooms.
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
  amount:=case when p.answers=0 then 0 when p.position=1 then 50 when p.position=2 then 30 else 10 end;
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


