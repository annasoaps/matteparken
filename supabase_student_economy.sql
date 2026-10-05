-- Matteparken: server-authoritative student economy v1
-- Run once in Supabase SQL Editor BEFORE deploying the matching index.html.
-- Protects kottar, school blind bags, park badges and habitat unlocks from localStorage edits.

create table if not exists public.student_economy (
  student_id uuid primary key references public.students(id) on delete cascade,
  nature_points integer not null default 0 check (nature_points >= 0),
  bonus_blind_bags integer not null default 0 check (bonus_blind_bags >= 0),
  badges jsonb not null default '{}'::jsonb,
  unlocked_habitats jsonb not null default '{"southwest":true,"northwest":false,"northeast":false,"southeast":false}'::jsonb,
  math_reward_rounds integer not null default 0 check (math_reward_rounds >= 0),
  tutorial_reward_claimed boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.student_math_reward_claims (
  student_id uuid not null references public.students(id) on delete cascade,
  activity_date date not null,
  activity_key text not null,
  claimed_units integer not null default 0 check (claimed_units >= 0),
  updated_at timestamptz not null default now(),
  primary key (student_id, activity_date, activity_key)
);

create table if not exists public.student_reward_claims (
  student_id uuid not null references public.students(id) on delete cascade,
  reward_kind text not null,
  reward_key text not null,
  claimed_at timestamptz not null default now(),
  primary key (student_id, reward_kind, reward_key)
);

create table if not exists public.student_purchases (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students(id) on delete cascade,
  purchase_kind text not null,
  item_id text not null default '',
  price integer not null check (price > 0),
  purchased_at timestamptz not null default now(),
  refunded_at timestamptz
);

alter table public.student_economy enable row level security;
alter table public.student_math_reward_claims enable row level security;
alter table public.student_reward_claims enable row level security;
alter table public.student_purchases enable row level security;

-- No direct writes are granted to students. All mutations go through validated RPCs.
revoke all on public.student_economy from anon, authenticated;
revoke all on public.student_math_reward_claims from anon, authenticated;
revoke all on public.student_reward_claims from anon, authenticated;
revoke all on public.student_purchases from anon, authenticated;

-- Resolve the claimed student for the current anonymous Supabase user without
-- depending on one hard-coded historical column name.
create or replace function public.matteparken_current_student_id()
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_col text;
  v_student uuid;
begin
  if v_uid is null then
    return null;
  end if;

  for v_col in
    select c.column_name
    from information_schema.columns c
    where c.table_schema = 'public'
      and c.table_name = 'students'
      and c.data_type = 'uuid'
      and c.column_name not in ('id','class_id')
    order by
      case c.column_name
        when 'claimed_by' then 1
        when 'auth_user_id' then 2
        when 'user_id' then 3
        when 'claimed_by_user_id' then 4
        when 'session_user_id' then 5
        when 'owner_id' then 6
        else 50
      end,
      c.column_name
  loop
    execute format('select id from public.students where %I = $1 limit 1', v_col)
      into v_student
      using v_uid;
    if v_student is not null then
      return v_student;
    end if;
  end loop;

  return null;
end;
$$;

revoke all on function public.matteparken_current_student_id() from public;
grant execute on function public.matteparken_current_student_id() to authenticated;

create or replace function public.matteparken_ensure_economy(p_student_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.student_economy(student_id)
  values (p_student_id)
  on conflict (student_id) do nothing;
end;
$$;

revoke all on function public.matteparken_ensure_economy(uuid) from public;

create or replace function public.student_get_economy()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_student uuid := public.matteparken_current_student_id();
  v_row public.student_economy%rowtype;
begin
  if v_student is null then
    return jsonb_build_object('ok',false,'reason','no_student_session');
  end if;

  perform public.matteparken_ensure_economy(v_student);
  select * into v_row from public.student_economy where student_id = v_student;

  return jsonb_build_object(
    'ok',true,
    'nature_points',v_row.nature_points,
    'bonus_blind_bags',v_row.bonus_blind_bags,
    'badges',v_row.badges,
    'unlocked_habitats',v_row.unlocked_habitats,
    'math_reward_rounds',v_row.math_reward_rounds
  );
end;
$$;

revoke all on function public.student_get_economy() from public;
grant execute on function public.student_get_economy() to authenticated;

create or replace function public.student_claim_math_reward(
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

  if p_game_id = 'multiplication' then
    if p_activity_key !~ '^multiplication:(10|[1-9])$' then
      return jsonb_build_object('ok',false,'reason','invalid_activity_key');
    end if;
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

  insert into public.student_math_reward_claims(student_id,activity_date,activity_key,claimed_units)
  values (v_student,v_today,p_activity_key,0)
  on conflict (student_id,activity_date,activity_key) do nothing;

  select claimed_units into v_claimed
  from public.student_math_reward_claims
  where student_id=v_student and activity_date=v_today and activity_key=p_activity_key
  for update;

  v_new_units := greatest(0, v_available - v_claimed);
  if v_new_units = 0 then
    perform public.matteparken_ensure_economy(v_student);
    select nature_points into v_balance from public.student_economy where student_id=v_student;
    return jsonb_build_object('ok',true,'granted',false,'balance',v_balance,'activity_count',v_count,'required',v_required);
  end if;

  -- All normal math reward rounds are worth 10 kottar.
  v_reward := v_new_units * 10;

  update public.student_math_reward_claims
     set claimed_units = v_available, updated_at = now()
   where student_id=v_student and activity_date=v_today and activity_key=p_activity_key;

  perform public.matteparken_ensure_economy(v_student);
  update public.student_economy
     set nature_points = nature_points + v_reward,
         math_reward_rounds = math_reward_rounds + v_new_units,
         updated_at = now()
   where student_id = v_student
   returning nature_points into v_balance;

  return jsonb_build_object(
    'ok',true,'granted',true,'amount',v_reward,'units',v_new_units,
    'balance',v_balance,'activity_count',v_count,'required',v_required
  );
end;
$$;

revoke all on function public.student_claim_math_reward(text,text) from public;
grant execute on function public.student_claim_math_reward(text,text) to authenticated;

create or replace function public.student_claim_tutorial_reward()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_student uuid := public.matteparken_current_student_id();
  v_balance integer;
  v_claimed boolean;
begin
  if v_student is null then
    return jsonb_build_object('ok',false,'reason','no_student_session');
  end if;
  perform public.matteparken_ensure_economy(v_student);

  select tutorial_reward_claimed into v_claimed
  from public.student_economy where student_id=v_student for update;

  if not v_claimed then
    update public.student_economy
       set nature_points=nature_points+60,
           tutorial_reward_claimed=true,
           badges=badges || jsonb_build_object('firstBloom',true),
           updated_at=now()
     where student_id=v_student
     returning nature_points into v_balance;
    return jsonb_build_object('ok',true,'granted',true,'amount',60,'balance',v_balance);
  end if;

  select nature_points into v_balance from public.student_economy where student_id=v_student;
  return jsonb_build_object('ok',true,'granted',false,'balance',v_balance);
end;
$$;

revoke all on function public.student_claim_tutorial_reward() from public;
grant execute on function public.student_claim_tutorial_reward() to authenticated;

create or replace function public.student_purchase(
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
  v_purchase uuid;
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

  perform public.matteparken_ensure_economy(v_student);
  select nature_points into v_balance
  from public.student_economy where student_id=v_student for update;

  if v_balance < v_price then
    return jsonb_build_object('ok',false,'reason','insufficient_funds','balance',v_balance,'price',v_price);
  end if;

  update public.student_economy
     set nature_points=nature_points-v_price, updated_at=now()
   where student_id=v_student
   returning nature_points into v_balance;

  insert into public.student_purchases(student_id,purchase_kind,item_id,price)
  values(v_student,v_kind,v_item,v_price)
  returning id into v_purchase;

  return jsonb_build_object('ok',true,'price',v_price,'balance',v_balance,'purchase_id',v_purchase);
end;
$$;

revoke all on function public.student_purchase(text,text) from public;
grant execute on function public.student_purchase(text,text) to authenticated;

create or replace function public.student_refund_recent_purchase(p_item_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_student uuid := public.matteparken_current_student_id();
  v_today date := (now() at time zone 'Europe/Stockholm')::date;
  v_purchase public.student_purchases%rowtype;
  v_balance integer;
begin
  if v_student is null then
    return jsonb_build_object('ok',false,'reason','no_student_session');
  end if;

  select * into v_purchase
  from public.student_purchases
  where student_id=v_student
    and item_id=trim(coalesce(p_item_id,''))
    and purchase_kind='catalog'
    and refunded_at is null
    and (purchased_at at time zone 'Europe/Stockholm')::date=v_today
  order by purchased_at desc
  limit 1
  for update;

  if v_purchase.id is null then
    perform public.matteparken_ensure_economy(v_student);
    select nature_points into v_balance from public.student_economy where student_id=v_student;
    return jsonb_build_object('ok',true,'refunded',false,'balance',v_balance);
  end if;

  update public.student_purchases set refunded_at=now() where id=v_purchase.id;
  update public.student_economy
     set nature_points=nature_points+v_purchase.price, updated_at=now()
   where student_id=v_student
   returning nature_points into v_balance;

  return jsonb_build_object('ok',true,'refunded',true,'amount',v_purchase.price,'balance',v_balance);
end;
$$;

revoke all on function public.student_refund_recent_purchase(text) from public;
grant execute on function public.student_refund_recent_purchase(text) to authenticated;

create or replace function public.student_claim_badge(p_badge_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_student uuid := public.matteparken_current_student_id();
  v_badge text := trim(coalesce(p_badge_id,''));
  v_badges jsonb;
begin
  if v_student is null then
    return jsonb_build_object('ok',false,'reason','no_student_session');
  end if;
  if v_badge not in ('firstBloom','parkBuilder','natureWatcher') then
    return jsonb_build_object('ok',false,'reason','invalid_badge');
  end if;

  perform public.matteparken_ensure_economy(v_student);
  update public.student_economy
     set badges = badges || jsonb_build_object(v_badge,true),
         updated_at=now()
   where student_id=v_student
   returning badges into v_badges;

  return jsonb_build_object('ok',true,'badges',v_badges);
end;
$$;

revoke all on function public.student_claim_badge(text) from public;
grant execute on function public.student_claim_badge(text) to authenticated;

create or replace function public.student_claim_habitat(p_habitat_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_student uuid := public.matteparken_current_student_id();
  v_badges jsonb;
  v_rounds integer;
  v_unlocked jsonb;
begin
  if v_student is null then
    return jsonb_build_object('ok',false,'reason','no_student_session');
  end if;
  if trim(coalesce(p_habitat_id,'')) <> 'northwest' then
    return jsonb_build_object('ok',false,'reason','not_available');
  end if;

  perform public.matteparken_ensure_economy(v_student);
  select badges,math_reward_rounds,unlocked_habitats
    into v_badges,v_rounds,v_unlocked
  from public.student_economy where student_id=v_student for update;

  if not (
    coalesce((v_badges->>'firstBloom')::boolean,false)
    and coalesce((v_badges->>'parkBuilder')::boolean,false)
    and coalesce((v_badges->>'natureWatcher')::boolean,false)
    and v_rounds >= 15
  ) then
    return jsonb_build_object('ok',false,'reason','requirements');
  end if;

  v_unlocked := v_unlocked || jsonb_build_object('northwest',true);
  update public.student_economy
     set unlocked_habitats=v_unlocked,updated_at=now()
   where student_id=v_student;

  return jsonb_build_object('ok',true,'unlocked_habitats',v_unlocked);
end;
$$;

revoke all on function public.student_claim_habitat(text) from public;
grant execute on function public.student_claim_habitat(text) to authenticated;

create or replace function public.matteparken_grant_school_bag(
  p_student uuid,
  p_kind text,
  p_key text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_inserted integer := 0;
  v_count integer;
begin
  insert into public.student_reward_claims(student_id,reward_kind,reward_key)
  values(p_student,p_kind,p_key)
  on conflict do nothing;
  get diagnostics v_inserted = row_count;

  perform public.matteparken_ensure_economy(p_student);
  if v_inserted > 0 then
    update public.student_economy
       set bonus_blind_bags=bonus_blind_bags+1,updated_at=now()
     where student_id=p_student
     returning bonus_blind_bags into v_count;
    return jsonb_build_object('ok',true,'granted',true,'bonus_blind_bags',v_count);
  end if;

  select bonus_blind_bags into v_count from public.student_economy where student_id=p_student;
  return jsonb_build_object('ok',true,'granted',false,'bonus_blind_bags',v_count);
end;
$$;

revoke all on function public.matteparken_grant_school_bag(uuid,text,text) from public;

create or replace function public.student_claim_daily_assignment_bag()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_student uuid := public.matteparken_current_student_id();
  v_class uuid;
  v_today date := (now() at time zone 'Europe/Stockholm')::date;
  v_total integer;
  v_done integer;
begin
  if v_student is null then return jsonb_build_object('ok',false,'reason','no_student_session'); end if;
  select class_id into v_class from public.students where id=v_student;

  select count(*) into v_total
  from public.assignments a
  where a.class_id=v_class and a.enabled=true and a.homework_id is null;

  if v_total=0 then return jsonb_build_object('ok',false,'reason','no_assignments'); end if;

  select count(*) into v_done
  from public.assignments a
  join public.student_assignment_progress p on p.assignment_id=a.id and p.student_id=v_student
  where a.class_id=v_class and a.enabled=true and a.homework_id is null
    and p.completed >= 1
    and coalesce(
      (p.completed_at at time zone 'Europe/Stockholm')::date,
      (p.updated_at at time zone 'Europe/Stockholm')::date,
      (p.last_active at time zone 'Europe/Stockholm')::date
    ) = v_today;

  if v_done < v_total then
    return jsonb_build_object('ok',false,'reason','incomplete','done',v_done,'total',v_total);
  end if;

  return public.matteparken_grant_school_bag(v_student,'daily_assignment',v_today::text);
end;
$$;

revoke all on function public.student_claim_daily_assignment_bag() from public;
grant execute on function public.student_claim_daily_assignment_bag() to authenticated;

create or replace function public.student_claim_homework_bag(p_homework_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_student uuid := public.matteparken_current_student_id();
  v_class uuid;
  v_total integer;
  v_done integer;
begin
  if v_student is null then return jsonb_build_object('ok',false,'reason','no_student_session'); end if;
  select class_id into v_class from public.students where id=v_student;

  if not exists(select 1 from public.homeworks h where h.id=p_homework_id and h.class_id=v_class) then
    return jsonb_build_object('ok',false,'reason','forbidden');
  end if;

  select count(*) into v_total from public.assignments where homework_id=p_homework_id;
  select count(*) into v_done
  from public.assignments a
  join public.student_assignment_progress p on p.assignment_id=a.id and p.student_id=v_student
  where a.homework_id=p_homework_id and p.completed>=1;

  if v_total=0 or v_done<v_total then
    return jsonb_build_object('ok',false,'reason','incomplete','done',v_done,'total',v_total);
  end if;

  return public.matteparken_grant_school_bag(v_student,'homework',p_homework_id::text);
end;
$$;

revoke all on function public.student_claim_homework_bag(uuid) from public;
grant execute on function public.student_claim_homework_bag(uuid) to authenticated;

create or replace function public.student_claim_quiz_bag(p_quiz_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_student uuid := public.matteparken_current_student_id();
begin
  if v_student is null then return jsonb_build_object('ok',false,'reason','no_student_session'); end if;
  if not exists(select 1 from public.quiz_attempts where student_id=v_student and quiz_id=p_quiz_id and completed_at is not null) then
    return jsonb_build_object('ok',false,'reason','no_attempt');
  end if;
  return public.matteparken_grant_school_bag(v_student,'quiz',p_quiz_id::text);
end;
$$;

revoke all on function public.student_claim_quiz_bag(uuid) from public;
grant execute on function public.student_claim_quiz_bag(uuid) to authenticated;

create or replace function public.student_consume_bonus_bag()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_student uuid := public.matteparken_current_student_id();
  v_count integer;
begin
  if v_student is null then return jsonb_build_object('ok',false,'reason','no_student_session'); end if;
  perform public.matteparken_ensure_economy(v_student);

  select bonus_blind_bags into v_count
  from public.student_economy where student_id=v_student for update;

  if v_count < 1 then
    return jsonb_build_object('ok',false,'reason','none_left','bonus_blind_bags',v_count);
  end if;

  update public.student_economy
     set bonus_blind_bags=bonus_blind_bags-1,updated_at=now()
   where student_id=v_student
   returning bonus_blind_bags into v_count;

  return jsonb_build_object('ok',true,'bonus_blind_bags',v_count);
end;
$$;

revoke all on function public.student_consume_bonus_bag() from public;
grant execute on function public.student_consume_bonus_bag() to authenticated;

comment on table public.student_economy is
  'Server-authoritative Matteparken economy. Client localStorage is only a cache once a student is connected.';
