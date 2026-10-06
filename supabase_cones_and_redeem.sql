-- Matteparken: kottar + redeem codes
-- Kör en gång i Supabase SQL Editor.
-- Avsiktligt liten migration: endast kottar och redeem-koder flyttas till servern.
-- Park, inventory, parkmärken, habitat, djur och dekorationer fortsätter sparas som tidigare.

create table if not exists public.student_cones (
  student_id uuid primary key references public.students(id) on delete cascade,
  balance integer not null default 0 check (balance >= 0),
  tutorial_reward_claimed boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.student_cone_claims (
  student_id uuid not null references public.students(id) on delete cascade,
  activity_date date not null,
  activity_key text not null,
  claimed_units integer not null default 0 check (claimed_units >= 0),
  updated_at timestamptz not null default now(),
  primary key (student_id, activity_date, activity_key)
);

create table if not exists public.student_cone_purchases (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students(id) on delete cascade,
  purchase_kind text not null,
  item_id text not null default '',
  price integer not null check (price > 0),
  purchased_at timestamptz not null default now()
);

create table if not exists public.redeem_codes (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  class_id uuid not null references public.classes(id) on delete cascade,
  reward_type text not null check (reward_type in ('cones','seedPack','decorBox','blindBag','autumnBox')),
  reward_amount integer not null default 1 check (reward_amount > 0),
  max_uses integer check (max_uses is null or max_uses > 0),
  expires_at timestamptz,
  enabled boolean not null default true,
  created_by uuid not null,
  created_at timestamptz not null default now()
);

create table if not exists public.redeem_redemptions (
  code_id uuid not null references public.redeem_codes(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,
  reward_type text not null,
  reward_amount integer not null,
  redeemed_at timestamptz not null default now(),
  primary key (code_id, student_id)
);

alter table public.student_cones enable row level security;
alter table public.student_cone_claims enable row level security;
alter table public.student_cone_purchases enable row level security;
alter table public.redeem_codes enable row level security;
alter table public.redeem_redemptions enable row level security;

revoke all on public.student_cones from anon, authenticated;
revoke all on public.student_cone_claims from anon, authenticated;
revoke all on public.student_cone_purchases from anon, authenticated;
revoke all on public.redeem_codes from anon, authenticated;
revoke all on public.redeem_redemptions from anon, authenticated;

-- Hitta den elev som hör till den aktuella anonyma Supabase-sessionen.
-- Viktigt: använd SECURITY INVOKER så att samma RLS-regler som redan fungerar
-- för elevsidans läsning av public.students avgör vilken rad som är elevens.
create or replace function public.matteparken_current_student_id()
returns uuid
language plpgsql
security invoker
set search_path = public
as $
declare
  v_student uuid;
begin
  if auth.uid() is null then
    return null;
  end if;

  select id
    into v_student
  from public.students
  limit 1;

  return v_student;
end;
$;

revoke all on function public.matteparken_current_student_id() from public;
grant execute on function public.matteparken_current_student_id() to authenticated;

create or replace function public.matteparken_ensure_cones(p_student_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.student_cones(student_id)
  values (p_student_id)
  on conflict (student_id) do nothing;
end;
$$;

revoke all on function public.matteparken_ensure_cones(uuid) from public;

create or replace function public.student_get_cones()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_student uuid := public.matteparken_current_student_id();
  v_balance integer;
begin
  if v_student is null then
    return jsonb_build_object('ok',false,'reason','no_student_session');
  end if;

  perform public.matteparken_ensure_cones(v_student);
  select balance into v_balance
  from public.student_cones
  where student_id = v_student;

  return jsonb_build_object('ok',true,'balance',v_balance);
end;
$$;

revoke all on function public.student_get_cones() from public;
grant execute on function public.student_get_cones() to authenticated;

-- Vanliga mattebelöningar. Servern räknar de rätta svar som redan registrerats
-- av record_math_activity och delar bara ut 10 kottar per komplett omgång.
create or replace function public.student_claim_math_cones(
  p_game_id text,
  p_activity_key text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_student uuid := public.matteparken_current_student_id();
  v_today date := (now() at time zone 'Europe/Stockholm')::date;
  v_required integer;
  v_count integer := 0;
  v_claimed integer := 0;
  v_available integer := 0;
  v_new_units integer := 0;
  v_reward integer := 0;
  v_balance integer := 0;
begin
  if v_student is null then
    return jsonb_build_object('ok',false,'reason','no_student_session');
  end if;

  p_game_id := trim(coalesce(p_game_id,''));
  p_activity_key := trim(coalesce(p_activity_key,''));

  if p_game_id = 'multiplication' and p_activity_key ~ '^multiplication:(10|[1-9])$' then
    v_required := 10;
  elsif p_game_id = 'equations' and p_activity_key = 'equations' then
    v_required := 3;
  elsif p_game_id = 'fractionArithmetic' and p_activity_key = 'fractionArithmetic' then
    v_required := 3;
  elsif p_game_id = 'fractionDecimal' and p_activity_key = 'fractionDecimal' then
    v_required := 8;
  elsif p_game_id = 'percentConvert' and p_activity_key = 'percentConvert' then
    v_required := 6;
  elsif p_game_id in ('pow10','mgn','sharePart','prefixMatch','unitConvert','statistics','scientificNotation')
        and p_activity_key = p_game_id then
    v_required := 10;
  else
    return jsonb_build_object('ok',false,'reason','unsupported_activity');
  end if;

  select coalesce(sum(a.count),0)::integer
    into v_count
  from public.student_daily_activity a
  where a.student_id = v_student
    and a.activity_date = v_today
    and a.game_id = p_game_id
    and a.activity_key = p_activity_key;

  v_available := floor(v_count::numeric / v_required)::integer;

  insert into public.student_cone_claims(student_id,activity_date,activity_key,claimed_units)
  values (v_student,v_today,p_activity_key,0)
  on conflict (student_id,activity_date,activity_key) do nothing;

  select claimed_units into v_claimed
  from public.student_cone_claims
  where student_id=v_student and activity_date=v_today and activity_key=p_activity_key
  for update;

  v_new_units := greatest(0, v_available - v_claimed);

  perform public.matteparken_ensure_cones(v_student);

  if v_new_units = 0 then
    select balance into v_balance from public.student_cones where student_id=v_student;
    return jsonb_build_object('ok',true,'granted',false,'balance',v_balance);
  end if;

  v_reward := v_new_units * 10;

  update public.student_cone_claims
     set claimed_units=v_available,updated_at=now()
   where student_id=v_student and activity_date=v_today and activity_key=p_activity_key;

  update public.student_cones
     set balance=balance+v_reward,updated_at=now()
   where student_id=v_student
   returning balance into v_balance;

  return jsonb_build_object('ok',true,'granted',true,'amount',v_reward,'balance',v_balance);
end;
$$;

revoke all on function public.student_claim_math_cones(text,text) from public;
grant execute on function public.student_claim_math_cones(text,text) to authenticated;

-- Startfröets fem korrekta svar ger 60 kottar en enda gång.
create or replace function public.student_claim_tutorial_cones()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_student uuid := public.matteparken_current_student_id();
  v_today date := (now() at time zone 'Europe/Stockholm')::date;
  v_count integer := 0;
  v_claimed boolean := false;
  v_balance integer := 0;
begin
  if v_student is null then
    return jsonb_build_object('ok',false,'reason','no_student_session');
  end if;

  select coalesce(sum(a.count),0)::integer
    into v_count
  from public.student_daily_activity a
  where a.student_id=v_student
    and a.activity_date=v_today
    and a.game_id='multiplication'
    and a.activity_key='multiplication';

  if v_count < 5 then
    return jsonb_build_object('ok',false,'reason','not_enough_activity');
  end if;

  perform public.matteparken_ensure_cones(v_student);

  select tutorial_reward_claimed into v_claimed
  from public.student_cones
  where student_id=v_student
  for update;

  if not v_claimed then
    update public.student_cones
       set balance=balance+60,tutorial_reward_claimed=true,updated_at=now()
     where student_id=v_student
     returning balance into v_balance;
    return jsonb_build_object('ok',true,'granted',true,'amount',60,'balance',v_balance);
  end if;

  select balance into v_balance from public.student_cones where student_id=v_student;
  return jsonb_build_object('ok',true,'granted',false,'balance',v_balance);
end;
$$;

revoke all on function public.student_claim_tutorial_cones() from public;
grant execute on function public.student_claim_tutorial_cones() to authenticated;

-- Alla köp som kostar kottar dras här. Föremålet/lådan sparas fortfarande lokalt
-- precis som tidigare; bara själva valutan är serverstyrd.
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

-- Läraren skapar en kod för den klass som är vald i Admin.
create or replace function public.teacher_create_redeem_code(
  p_class_id uuid,
  p_code text,
  p_reward_type text,
  p_reward_amount integer default 1,
  p_max_uses integer default null,
  p_expires_at timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text := upper(regexp_replace(trim(coalesce(p_code,'')),'\s+','','g'));
  v_type text := trim(coalesce(p_reward_type,''));
  v_amount integer := greatest(1,coalesce(p_reward_amount,1));
  v_id uuid;
begin
  if not public.matteparken_teacher_owns_class(p_class_id) then
    return jsonb_build_object('ok',false,'reason','forbidden');
  end if;

  if v_code !~ '^[A-ZÅÄÖ0-9_-]{4,24}$' then
    return jsonb_build_object('ok',false,'reason','invalid_code');
  end if;

  if v_type not in ('cones','seedPack','decorBox','blindBag','autumnBox') then
    return jsonb_build_object('ok',false,'reason','invalid_reward');
  end if;

  if v_type='cones' then
    v_amount := least(v_amount,1000);
  else
    v_amount := least(v_amount,10);
  end if;

  if p_max_uses is not null and p_max_uses < 1 then
    return jsonb_build_object('ok',false,'reason','invalid_max_uses');
  end if;

  insert into public.redeem_codes(
    code,class_id,reward_type,reward_amount,max_uses,expires_at,created_by
  )
  values(
    v_code,p_class_id,v_type,v_amount,p_max_uses,p_expires_at,auth.uid()
  )
  returning id into v_id;

  return jsonb_build_object('ok',true,'id',v_id,'code',v_code);
exception
  when unique_violation then
    return jsonb_build_object('ok',false,'reason','code_exists');
end;
$$;

revoke all on function public.teacher_create_redeem_code(uuid,text,text,integer,integer,timestamptz) from public;
grant execute on function public.teacher_create_redeem_code(uuid,text,text,integer,integer,timestamptz) to authenticated;

create or replace function public.teacher_list_redeem_codes(p_class_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_result jsonb;
begin
  if not public.matteparken_teacher_owns_class(p_class_id) then
    return jsonb_build_object('ok',false,'reason','forbidden');
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id',r.id,
        'code',r.code,
        'reward_type',r.reward_type,
        'reward_amount',r.reward_amount,
        'max_uses',r.max_uses,
        'uses',(select count(*) from public.redeem_redemptions x where x.code_id=r.id),
        'expires_at',r.expires_at,
        'enabled',r.enabled,
        'created_at',r.created_at
      )
      order by r.created_at desc
    ),
    '[]'::jsonb
  )
  into v_result
  from public.redeem_codes r
  where r.class_id=p_class_id;

  return jsonb_build_object('ok',true,'codes',v_result);
end;
$$;

revoke all on function public.teacher_list_redeem_codes(uuid) from public;
grant execute on function public.teacher_list_redeem_codes(uuid) to authenticated;

create or replace function public.teacher_set_redeem_code_enabled(
  p_code_id uuid,
  p_enabled boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_class uuid;
begin
  select class_id into v_class from public.redeem_codes where id=p_code_id;
  if v_class is null or not public.matteparken_teacher_owns_class(v_class) then
    return jsonb_build_object('ok',false,'reason','forbidden');
  end if;

  update public.redeem_codes
     set enabled=coalesce(p_enabled,false)
   where id=p_code_id;

  return jsonb_build_object('ok',true,'enabled',coalesce(p_enabled,false));
end;
$$;

revoke all on function public.teacher_set_redeem_code_enabled(uuid,boolean) from public;
grant execute on function public.teacher_set_redeem_code_enabled(uuid,boolean) to authenticated;

-- Eleven löser in en kod. Samma elev kan aldrig lösa in samma kod två gånger.
create or replace function public.student_redeem_code(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_student uuid := public.matteparken_current_student_id();
  v_class uuid;
  v_code text := upper(regexp_replace(trim(coalesce(p_code,'')),'\s+','','g'));
  v_row public.redeem_codes%rowtype;
  v_uses integer;
  v_balance integer;
begin
  if v_student is null then
    return jsonb_build_object('ok',false,'reason','no_student_session');
  end if;

  select class_id into v_class from public.students where id=v_student;

  select * into v_row
  from public.redeem_codes
  where code=v_code and class_id=v_class
  for update;

  if v_row.id is null then
    return jsonb_build_object('ok',false,'reason','not_found');
  end if;
  if not v_row.enabled then
    return jsonb_build_object('ok',false,'reason','disabled');
  end if;
  if v_row.expires_at is not null and v_row.expires_at < now() then
    return jsonb_build_object('ok',false,'reason','expired');
  end if;
  if exists(select 1 from public.redeem_redemptions where code_id=v_row.id and student_id=v_student) then
    return jsonb_build_object('ok',false,'reason','already_redeemed');
  end if;

  if v_row.max_uses is not null then
    select count(*)::integer into v_uses
    from public.redeem_redemptions
    where code_id=v_row.id;
    if v_uses >= v_row.max_uses then
      return jsonb_build_object('ok',false,'reason','used_up');
    end if;
  end if;

  insert into public.redeem_redemptions(code_id,student_id,reward_type,reward_amount)
  values(v_row.id,v_student,v_row.reward_type,v_row.reward_amount);

  if v_row.reward_type='cones' then
    perform public.matteparken_ensure_cones(v_student);
    update public.student_cones
       set balance=balance+v_row.reward_amount,updated_at=now()
     where student_id=v_student
     returning balance into v_balance;
  else
    perform public.matteparken_ensure_cones(v_student);
    select balance into v_balance from public.student_cones where student_id=v_student;
  end if;

  return jsonb_build_object(
    'ok',true,
    'reward_type',v_row.reward_type,
    'reward_amount',v_row.reward_amount,
    'balance',v_balance
  );
end;
$$;

revoke all on function public.student_redeem_code(text) from public;
grant execute on function public.student_redeem_code(text) to authenticated;

comment on table public.student_cones is
  'Serverstyrt kott-saldo. Övrig parkdata är avsiktligt fortfarande lokal.';
comment on table public.redeem_codes is
  'Lärarskapade belöningskoder per klass; varje elev kan lösa in en kod högst en gång.';
