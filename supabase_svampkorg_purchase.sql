-- Aktiveras först när Svampstigen är godkänd.
-- Lägger till 'mushroomBasket' (60 kottar) i samma priskontroll som andra katalogföremål.

create or replace function public.student_spend_cones(
  p_purchase_kind text,
  p_item_id text default ''
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_student uuid := public.matteparken_current_student_id();
  v_kind text := trim(coalesce(p_purchase_kind,''));
  v_item text := trim(coalesce(p_item_id,''));
  v_price integer;
  v_balance integer;
begin
  if v_student is null then
    return jsonb_build_object('ok',false,'reason','no_student_session');
  end if;

  v_price := case
    when v_kind='seedPack' then 30
    when v_kind='decorBox' then 100
    when v_kind='seasonal' and v_item in ('autumn','halloween','christmas','valentine') then 100
    when v_kind='catalog' and v_item='flowerShrub' then 35
    when v_kind='catalog' and v_item='bench' then 50
    when v_kind='catalog' and v_item='birdhouse' then 60
    when v_kind='catalog' and v_item='mushroomBasket' then 60
    when v_kind='catalog' and v_item='birch' then 60
    when v_kind='catalog' and v_item='spruce' then 55
    when v_kind='catalog' and v_item='pine' then 55
    when v_kind='catalog' and v_item='oak' then 70
    when v_kind='catalog' and v_item='miniJetty' then 80
    else null
  end;

  if v_price is null then
    return jsonb_build_object('ok',false,'reason','invalid_purchase');
  end if;

  perform public.matteparken_ensure_cones(v_student);

  select balance into v_balance
  from public.student_cones
  where student_id=v_student
  for update;

  if v_balance < v_price then
    return jsonb_build_object('ok',false,'reason','insufficient_funds','balance',v_balance,'price',v_price);
  end if;

  update public.student_cones
     set balance=balance-v_price,updated_at=now()
   where student_id=v_student
   returning balance into v_balance;

  insert into public.student_cone_purchases(student_id,purchase_kind,item_id,price)
  values(v_student,v_kind,v_item,v_price);

  return jsonb_build_object('ok',true,'price',v_price,'balance',v_balance);
end;
$$;

revoke all on function public.student_spend_cones(text,text) from public;
grant execute on function public.student_spend_cones(text,text) to authenticated;