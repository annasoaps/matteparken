-- Matteparken: köp-ID och dubbleringsskydd.
-- Befintliga saldon, köp, elevkonton och parker ändras inte.
-- Körs som en additiv migrering. Äldre klienter använder en kompatibilitetsfunktion.

alter table public.student_cone_purchases
  add column if not exists request_id uuid;

create unique index if not exists student_cone_purchases_student_request_unique
  on public.student_cone_purchases(student_id,request_id)
  where request_id is not null;

create index if not exists student_cone_purchases_recent_item_idx
  on public.student_cone_purchases(student_id,purchase_kind,item_id,purchased_at desc);

create or replace function public.student_spend_cones_v2(
  p_purchase_kind text, p_item_id text, p_request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $body$
declare
  v_student uuid := public.matteparken_current_student_id();
  v_kind text := trim(coalesce(p_purchase_kind,''));
  v_item text := trim(coalesce(p_item_id,''));
  v_price integer;
  v_balance integer;
  v_old public.student_cone_purchases%rowtype;
  v_purchase_id uuid;
  v_last_purchase timestamptz;
  v_wait_seconds integer := 8;
begin
  if v_student is null then
    return jsonb_build_object('ok',false,'reason','no_student_session');
  end if;
  if p_request_id is null then
    return jsonb_build_object('ok',false,'reason','missing_request_id');
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
  -- Samtliga köp för samma elev serialiseras på elevens saldorad.
  select balance into v_balance from public.student_cones
    where student_id = v_student for update;

  -- En nätverksomförsök med samma ID får aldrig dra kottar igen.
  select * into v_old from public.student_cone_purchases
    where student_id=v_student and request_id=p_request_id;
  if found then
    if v_old.purchase_kind <> v_kind or v_old.item_id <> v_item then
      return jsonb_build_object('ok',false,'reason','request_id_reused','balance',v_balance);
    end if;
    return jsonb_build_object(
      'ok',true,'already_processed',true,'purchase_id',v_old.id,
      'price',v_old.price,'balance',v_balance
    );
  end if;

  -- Även olika köp-ID av samma vara tätt efter varandra stoppas.
  -- Detta skyddar också äldre webbläsarversioner utan köp-ID.
  select purchased_at into v_last_purchase
    from public.student_cone_purchases
    where student_id=v_student and purchase_kind=v_kind and item_id=v_item
    order by purchased_at desc limit 1;
  if v_last_purchase is not null
     and v_last_purchase > clock_timestamp() - (v_wait_seconds * interval '1 second') then
    return jsonb_build_object(
      'ok',false,'reason','please_wait','retry_after_seconds',v_wait_seconds,
      'balance',v_balance
    );
  end if;

  if v_balance < v_price then
    return jsonb_build_object(
      'ok',false,'reason','insufficient_funds','balance',v_balance,'price',v_price
    );
  end if;

  update public.student_cones
    set balance=balance-v_price,updated_at=now()
    where student_id=v_student
    returning balance into v_balance;

  insert into public.student_cone_purchases
    (student_id,purchase_kind,item_id,price,request_id)
    values(v_student,v_kind,v_item,v_price,p_request_id)
    returning id into v_purchase_id;

  return jsonb_build_object(
    'ok',true,'already_processed',false,'purchase_id',v_purchase_id,
    'price',v_price,'balance',v_balance
  );
end;
$body$;

revoke all on function public.student_spend_cones_v2(text,text,uuid) from public;
revoke all on function public.student_spend_cones_v2(text,text,uuid) from anon;
grant execute on function public.student_spend_cones_v2(text,text,uuid) to authenticated;

-- Bakåtkompatibel ingång: äldre sidor får samma 8-sekundersskydd.
create or replace function public.student_spend_cones(
  p_purchase_kind text, p_item_id text default ''
)
returns jsonb
language sql
security definer
set search_path = ''
as $body$
  select public.student_spend_cones_v2(
    p_purchase_kind,p_item_id,gen_random_uuid()
  );
$body$;

revoke all on function public.student_spend_cones(text,text) from public;
revoke all on function public.student_spend_cones(text,text) from anon;
grant execute on function public.student_spend_cones(text,text) to authenticated;