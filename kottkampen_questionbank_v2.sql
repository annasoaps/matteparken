-- Kottkampen v2: extensive curriculum-based task variants and an anti-guessing scoring rule.
-- The new question generator is designed from existing percent, fraction, interest and other
-- game content in Matteparken, but does NOT change the standalone teaching games.
-- Correct answer: +100. Incorrect answer: -50. Chance guessing (1 in 4) yields -12.5 expected.
-- Real cones are separate and cannot be lost by answering incorrectly.

create or replace function private.kottkamp_fmt(p numeric)
returns text language sql immutable set search_path='' as $fmt$
 select replace(trim(trailing '.' from to_char(round(p,4),'FM99999999990.9999')),'.',',')
$fmt$;

create or replace function private.kottkamp_gcd(p integer,q integer)
returns integer language plpgsql immutable set search_path='' as $gcd$
declare a integer:=abs(p); b integer:=abs(q); t integer;
begin
 while b<>0 loop t:=mod(a,b);a:=b;b:=t;end loop;
 return greatest(a,1);
end $gcd$;

create or replace function private.kottkamp_question_for(p_session uuid,p_index integer)
returns public.kottkamp_questions
language plpgsql security definer set search_path='' as $question$
declare
 s public.kottkamp_sessions; q public.kottkamp_questions;
 g text; prompt_text text; result_value numeric; answer_text text;
 opts text[]; frac_pool text[]:=array['1/2','1/4','3/4','1/5','2/5','3/5','4/5','1/10','3/10','7/10','9/10','1/100','9/100','1/1','1/20','3/20','1/8','3/8','5/8','7/8','1/25','3/25'];
 frac text; n integer; d integer; n2 integer; d2 integer; numerator integer; denominator integer;
 fraction_mode boolean:=false; own_distractors boolean:=false;
 a integer; b integer; pc numeric; base_value numeric; part_value numeric; after_value numeric;
 delta numeric; k integer; v integer; swap text; tries integer; style integer;
 story text; context_name text; unit_name text; scene_type text;
 rows_count integer; cols_count integer; filled integer; exp integer; factor numeric;
 opt1 text; opt2 text; opt3 text;
begin
 select * into q from public.kottkamp_questions where session_id=p_session and question_index=p_index;
 if found then return q; end if;
 select * into s from public.kottkamp_sessions where id=p_session;
 if s.id is null or p_index<0 or p_index>1200 then raise exception 'invalid_question'; end if;
 -- Draw each selected area once per cycle, in a newly randomized order.
 select candidate.game_id into g
 from unnest(s.games) as candidate(game_id)
 where not exists(
  select 1 from public.kottkamp_questions existing
  where existing.session_id=p_session
    and existing.question_index >= (p_index / array_length(s.games,1)) * array_length(s.games,1)
    and existing.question_index < p_index
    and existing.game_id=candidate.game_id
 )
 order by random() limit 1;
 if g is null then g:=s.games[(p_index % array_length(s.games,1))+1];end if;
 for tries in 1..40 loop
  prompt_text:=null; answer_text:=null; result_value:=null; delta:=null;
  own_distractors:=false; fraction_mode:=false;
  a:=1+floor(random()*15)::integer;
  b:=1+floor(random()*12)::integer;
  pc:=(array[5,10,12,15,20,25,30,35,40,50,60,70,75,80,90])[1+floor(random()*15)::int];
  style:=floor(random()*5)::int;
  case g
   when 'percentConvert' then
    frac:=frac_pool[1+floor(random()*array_length(frac_pool,1))::int];
    if random()<0.24 then frac:=(1+floor(random()*99)::int)::text||'/100'; end if;
    n:=split_part(frac,'/',1)::int;d:=split_part(frac,'/',2)::int;
    result_value:=n::numeric/d;
    if style=0 then
     prompt_text:=frac||' = ? %';
     result_value:=result_value*100;delta:=5;
    elsif style=1 then
     prompt_text:=private.kottkamp_fmt(result_value*100)||' % = ? i decimalform';
     delta:=0.05;
    elsif style=2 then
     prompt_text:=private.kottkamp_fmt(result_value)||' = ? %';
     result_value:=result_value*100;delta:=5;
    else
     prompt_text:=private.kottkamp_fmt(result_value*100)||' % = ? i bråkform';
     answer_text:=frac;fraction_mode:=true;own_distractors:=true;
     -- Use alternate canonical fractions, avoiding the value of the correct one.
     select array_agg(x.f) into opts from (
       select f from unnest(frac_pool) f
       where f<>frac and split_part(f,'/',1)::numeric/split_part(f,'/',2)::numeric<>n::numeric/d
       order by random() limit 3
     ) x;
     opt1:=opts[1];opt2:=opts[2];opt3:=opts[3];
    end if;
   when 'sharePart' then
    if random()<0.72 then
     select z.r,z.c,z.f into rows_count,cols_count,filled from
      (values (2,5,1),(2,5,3),(2,5,6),(2,5,7),(2,5,9),
      (1,5,1),(1,5,2),(1,5,4),(1,4,1),(1,4,3),
      (10,10,1),(10,10,9),(10,10,17),(10,10,23),
      (10,10,37),(10,10,42),(10,10,64),(10,10,75)) z(r,c,f) order by random() limit 1;
    else
     rows_count:=(array[2,4,5,10])[1+floor(random()*4)::int];
     cols_count:=(array[4,5,10])[1+floor(random()*3)::int];
     filled:=1+floor(random()*(rows_count*cols_count-1))::int;
    end if;
    prompt_text:='En bild har '||rows_count*cols_count||' rutor och '||filled||' av dem är färgade. Hur stor andel är färgad (i %)?';
    result_value:=100::numeric*filled/(rows_count*cols_count);delta:=5;
   when 'percentChange' then
    select z.label,z.category,z.unit into context_name,scene_type,unit_name from
     (values ('parkbänkens pris','price','kr'),('fågelbadets pris','price','kr'),
      ('fågelholkens pris','price','kr'),('insektshotellets pris','price','kr'),
      ('fiskestolens pris','price','kr'),('abborrens vikt','fish','g'),
      ('mörtens vikt','fish','g'),('björknans vikt','fish','g'),
      ('sarvens vikt','fish','g'),('braxens vikt','fish','g'),
      ('sutarens vikt','fish','g'),('gäddans vikt','fish','g'),
      ('antalet ekorrar','wildlife','stycken'),('antalet nyckelpigor','wildlife','stycken'),
      ('antalet igelkottar','wildlife','stycken'),('antalet fjärilar','wildlife','stycken'),
      ('antalet grodor','wildlife','stycken'),('antalet svarta katter','wildlife','stycken'),
      ('antalet pumpor','stock','stycken'),('antalet höstblommor','stock','stycken'),
      ('antalet lövkorgar','stock','stycken'),('antalet äppelkorgar','stock','stycken'),
      ('antalet lövhögar','stock','stycken'),('antalet soppar','stock','stycken'),
      ('antalet fjällskivlingar','stock','stycken')
     ) z(label,category,unit) order by random() limit 1;
    pc:=(array[10,12,15,20,25,30,40,50])[1+floor(random()*8)::int];
    base_value:=(array[100,120,150,160,200,240,250,300,320,400,480,500,600,800,1000])[1+floor(random()*15)::int];
    if scene_type in ('wildlife','stock') then
     base_value:=(array[20,25,30,40,50,60,100,120,160,200])[1+floor(random()*10)::int];
     pc:=(array[10,20,25,30,40,50])[1+floor(random()*6)::int];
    end if;
    if random()<0.5 then after_value:=base_value*(100+pc)/100;story:='ökat';
    else after_value:=base_value*(100-pc)/100;story:='minskat';end if;
    prompt_text:='I Matteparken har '||context_name||' ändrats från '||private.kottkamp_fmt(base_value)||' '||unit_name||' till '||private.kottkamp_fmt(after_value)||' '||unit_name||'. Hur många procent har värdet '||story||'?';
    result_value:=pc;delta:=5;
   when 'percentPart' then
    if random()<0.50 then
     select z.p,z.whole,z.prompt into pc,base_value,prompt_text from
     (values
      (20,450,'Ett spel kostar 450 kr. Priset sänks med 20 %. Hur många kronor billigare blir spelet?'),
      (25,400,'En ryggsäck kostar 400 kr och säljs med 25 % rabatt. Hur stor är rabatten i kronor?'),
      (10,250,'En bok kostar 250 kr och har 10 % rabatt. Hur många kronor blir rabatten?'),
      (15,200,'På blomsterängen växer 200 blommor. 15 % är gula. Hur många gula blommor finns det?'),
      (30,240,'Parkvakten räknar 240 grodor. 30 % finns vid dammen. Hur många grodor är det?'),
      (5,600,'En skejtboard kostar 600 kr. Du får 5 % rabatt. Hur många kronor sparar du?'),
      (35,1200,'En cykel kostar 1 200 kr och sänks med 35 %. Hur stor är rabatten i kronor?'),
      (50,60,'Det skördas 60 morötter och 50 % säljs. Hur många morötter säljs?')
     ) z(p,whole,prompt) order by random() limit 1;
    else
     base_value:=(array[60,80,100,120,150,200,240,250,300,400,450,500,600,800,1000,1200])[1+floor(random()*16)::int];
     pc:=(array[5,10,15,20,25,30,35,40,50,60,70,75,80])[1+floor(random()*13)::int];
     story:=(array['blommor i parken','kottar i förrådet','plantor i växthuset','fiskar i sjön','böcker på hyllan','kronor i kassan'])[1+floor(random()*6)::int];
     prompt_text:='Det finns '||private.kottkamp_fmt(base_value)||' '||story||'. Hur många är '||private.kottkamp_fmt(pc)||' % av det hela?';
    end if;
    result_value:=pc*base_value/100;delta:=case when result_value<10 then 1 else 5 end;
   when 'whole' then
    if random()<0.50 then
     d:=(array[3,4,5,6,8])[1+floor(random()*5)::int];
     n:=1+floor(random()*(d-1))::int;
     a:=2+floor(random()*40)::int;
     prompt_text:=n||'/'||d||' av ett tal är '||(n*a)||'. Vilket är hela talet?';
     result_value:=d*a;
    else
     pc:=(array[10,20,25,30,40,50,60,70,75,80,90])[1+floor(random()*11)::int];
     base_value:=(array[40,60,80,100,120,150,160,200,240,300,400,500,600,800,1000])[1+floor(random()*15)::int];
     part_value:=pc*base_value/100;
     prompt_text:=private.kottkamp_fmt(pc)||' % av ett tal är '||private.kottkamp_fmt(part_value)||'. Vilket är hela talet?';
     result_value:=base_value;
    end if;
    delta:=case when result_value<50 then 5 else 10 end;
   when 'fractionDecimal' then
    frac:=(array['1/2','1/4','3/4','1/5','2/5','3/5','4/5','1/10','3/10','7/10','9/10','1/8','3/8','5/8','7/8','1/20','3/20'])[1+floor(random()*17)::int];
    -- Extend the original matching-game pairs with many exactly representable
    -- decimal fractions; reduce each new pair before asking for simplest form.
    if random()<0.73 then
     d:=(array[2,4,5,8,10,20,25,40,50,100])[1+floor(random()*10)::int];
     n:=1+floor(random()*(d-1))::int;
     v:=private.kottkamp_gcd(n,d);
     frac:=(n/v)||'/'||(d/v);
    end if;
    n:=split_part(frac,'/',1)::int;d:=split_part(frac,'/',2)::int;
    if random()<0.5 then
     prompt_text:=frac||' = ? i decimalform';
     result_value:=n::numeric/d;delta:=0.05;
    else
     prompt_text:=private.kottkamp_fmt(n::numeric/d)||' = ? i bråkform (enklaste form)';
     answer_text:=frac;fraction_mode:=true;own_distractors:=true;
     select array_agg(x.f) into opts from
      (select f from unnest(frac_pool) f where f<>frac and split_part(f,'/',1)::numeric/split_part(f,'/',2)::numeric<>n::numeric/d order by random() limit 3) x;
     opt1:=opts[1];opt2:=opts[2];opt3:=opts[3];
    end if;
   when 'fractionArithmetic' then
    n:=1+floor(random()*5)::int; d:=n+1+floor(random()*8)::int;
    n2:=1+floor(random()*5)::int; d2:=n2+1+floor(random()*8)::int;
    style:=floor(random()*4)::int;
    if style=0 then numerator:=n*d2+n2*d;denominator:=d*d2;story:='+';
    elsif style=1 then
     if n::numeric/d<n2::numeric/d2 then
      a:=n;n:=n2;n2:=a;a:=d;d:=d2;d2:=a;
     end if;
     numerator:=n*d2-n2*d;denominator:=d*d2;story:='−';
    elsif style=2 then numerator:=n*n2;denominator:=d*d2;story:='×';
    else numerator:=n*d2;denominator:=d*n2;story:='÷';end if;
    a:=private.kottkamp_gcd(numerator,denominator);numerator:=numerator/a;denominator:=denominator/a;
    prompt_text:=n||'/'||d||' '||story||' '||n2||'/'||d2||' = ? (svara som bråk i enklaste form)';
    answer_text:=numerator||'/'||denominator;fraction_mode:=true;own_distractors:=true;
    opt1:=(numerator+1)||'/'||denominator;
    opt2:=(numerator+2)||'/'||denominator;
    opt3:=(numerator+3)||'/'||denominator;
   when 'multiplication' then
    a:=1+floor(random()*10)::int;b:=1+floor(random()*10)::int;
    prompt_text:=a||' × '||b||' = ?';result_value:=a*b;delta:=a;
   when 'equations' then
    a:=2+floor(random()*8)::int;b:=1+floor(random()*15)::int;n:=1+floor(random()*20)::int;
    prompt_text:=a||'x + '||b||' = '||(a*n+b)||'. Vad är x?';
    result_value:=n;delta:=1;
   when 'pow10' then
    factor:=(array[10,100,1000])[1+floor(random()*3)::int];
    base_value:=(1+floor(random()*990)::int)/10.0;
    if random()<0.5 then
     prompt_text:=private.kottkamp_fmt(base_value)||' × '||private.kottkamp_fmt(factor)||' = ?';
     result_value:=base_value*factor;delta:=factor/10;
    else
     prompt_text:=private.kottkamp_fmt(base_value*factor)||' ÷ '||private.kottkamp_fmt(factor)||' = ?';
     result_value:=base_value;delta:=1;
    end if;
   when 'interest' then
    select z.p,z.amount,z.months,z.kind,z.label into pc,base_value,n,scene_type,context_name from
     (values (4,5000,12,'save','sparkonto'),(5,4000,12,'save','kottsparandet'),
      (5,4000,12,'loan','cykellånet'),(3,8000,12,'loan','datorlånet'),
      (6,3000,6,'save','halvårssparandet'),(4,6000,6,'save','sparkontot'),
      (4,8000,3,'loan','utflyktslånet'),(6,6000,6,'loan','utflyktslånet')
     ) z(p,amount,months,kind,label) order by random() limit 1;
    if random()<0.35 then
     base_value:=(array[2000,3000,4000,5000,6000,8000,10000])[1+floor(random()*7)::int];
     pc:=(array[2,3,4,5,6,7,10])[1+floor(random()*7)::int];
     n:=(array[3,6,12])[1+floor(random()*3)::int];
    end if;
    story:=case when n=12 then 'ett år' when n=6 then 'sex månader' else 'tre månader' end;
    if scene_type='loan' and random()<0.35 then
     prompt_text:='Ett lån på '||private.kottkamp_fmt(base_value)||' kr har '||pc||' % årsränta. Vad är totalsumman att betala tillbaka efter '||story||' om enbart räntan läggs till?';
     result_value:=base_value+pc*base_value*n/1200;
    else
     prompt_text:='På '||context_name||' finns '||private.kottkamp_fmt(base_value)||' kr med '||pc||' % årsränta. Hur många kronor blir räntan efter '||story||'?';
     result_value:=pc*base_value*n/1200;
    end if;
    delta:=case when result_value<100 then 10 else 50 end;
   when 'unitConvert' then
    select z.label,z.value into prompt_text,result_value from
    (values ('250 cm = ? m',2.5),('3,4 m = ? cm',340),('7 500 mm = ? m',7.5),
     ('2,5 kg = ? g',2500),('650 g = ? kg',0.65),('1,8 l = ? ml',1800),
     ('450 ml = ? l',0.45),('4,2 m = ? mm',4200)
    ) z(label,value) order by random() limit 1;
    if random()<0.55 then
     a:=1+floor(random()*100)::int;
     case floor(random()*6)::int
      when 0 then prompt_text:=a||' cm = ? m';result_value:=a/100.0;
      when 1 then prompt_text:=a||' m = ? cm';result_value:=a*100;
      when 2 then prompt_text:=a||' kg = ? g';result_value:=a*1000;
      when 3 then prompt_text:=a||' g = ? kg';result_value:=a/1000.0;
      when 4 then prompt_text:=a||' l = ? ml';result_value:=a*1000;
      else prompt_text:=a||' ml = ? l';result_value:=a/1000.0;
     end case;
    end if;
   when 'prefixMatch' then
    select z.from_unit,z.to_unit,z.factor into context_name,unit_name,factor from
     (values ('kilometer','meter',1000::numeric),('hektogram','gram',100),
     ('decimeter','meter',0.1),('centimeter','meter',0.01),('millimeter','meter',0.001),
     ('kilogram','gram',1000),('decimter','centimeter',10)) z(from_unit,to_unit,factor)
     order by random() limit 1;
    a:=1+floor(random()*300)::int;
    if context_name='decimter' then context_name:='decimeter';end if;
    prompt_text:=a||' '||context_name||' = ? '||unit_name;
    result_value:=a*factor;
   when 'statistics' then
    a:=2+floor(random()*200)::int;style:=floor(random()*3)::int;
    if style=0 then prompt_text:='Medelvärdet av '||a||', '||(a+2)||', '||(a+4)||', '||(a+6)||', '||(a+8)||' = ?';result_value:=a+4;
    elsif style=1 then prompt_text:='Medianen av '||(a+8)||', '||a||', '||(a+4)||', '||(a+2)||', '||(a+6)||' = ?';result_value:=a+4;
    else prompt_text:='Typvärdet i '||a||', '||(a+2)||', '||(a+2)||', '||(a+5)||', '||(a+7)||' = ?';result_value:=a+2;end if;
    delta:=1;
   when 'scientificNotation' then
    a:=1+floor(random()*9)::int;exp:=2+floor(random()*6)::int;
    if random()<0.5 then
     prompt_text:=(a*power(10,exp))||' i grundpotensform = ?';
     answer_text:=a||' × 10^'||exp;own_distractors:=true;
     opt1:=a||' × 10^'||(exp+1);
     opt2:=(a+1)||' × 10^'||exp;
     opt3:=a||' × 10^'||(exp-1);
    else
     prompt_text:=a||' × 10^'||exp||' = ?';
     result_value:=a*power(10,exp);delta:=power(10,exp);
    end if;
   else
    raise exception 'unsupported_game: %',g;
  end case;
  if prompt_text is null then raise exception 'empty_question'; end if;
  exit when not exists(select 1 from public.kottkamp_questions where session_id=p_session and prompt=prompt_text);
 end loop;
 if not own_distractors then
  answer_text:=private.kottkamp_fmt(result_value);
  if delta is null then
   delta:=case when abs(result_value)<0.1 then 0.01 when abs(result_value)<2 then 0.1 when abs(result_value)<20 then 1 else 10 end;
  end if;
  if result_value>0 and result_value-delta<0 then delta:=result_value;end if;
  opt1:=private.kottkamp_fmt(result_value+delta);
  opt2:=private.kottkamp_fmt(result_value-delta);
  opt3:=private.kottkamp_fmt(result_value+2*delta);
 end if;
 if answer_text is null or opt1 is null or opt2 is null or opt3 is null or
  answer_text=opt1 or answer_text=opt2 or answer_text=opt3 or opt1=opt2 or opt1=opt3 or opt2=opt3 then
  raise exception 'duplicate_answers_in_%',g;
 end if;
 opts:=array[answer_text,opt1,opt2,opt3];
 for k in reverse 4..2 loop
  v:=1+floor(random()*k)::int;
  swap:=opts[k];opts[k]:=opts[v];opts[v]:=swap;
 end loop;
 insert into public.kottkamp_questions(session_id,question_index,game_id,prompt,options,correct_index)
 values(p_session,p_index,g,prompt_text,opts,array_position(opts,answer_text)-1)
 on conflict(session_id,question_index) do nothing;
 select * into q from public.kottkamp_questions where session_id=p_session and question_index=p_index;
 return q;
end $question$;

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
   'score',p.score,'correct',p.correct_count) order by p.score desc,p.correct_count desc),'[]'::jsonb)
 into data from public.kottkamp_players p join public.students st on st.id=p.student_id where p.session_id=p_id;
 return jsonb_build_object('ok',true,'session',jsonb_build_object('id',s.id,'title',s.title,
   'status',s.status,'mode',s.mode,'minutes',s.minutes,'question_count',s.question_count,
   'started_at',s.started_at,'paused_at',s.paused_at,'paused_seconds',s.paused_seconds),
   'me',jsonb_build_object('score',pl.score,'correct',pl.correct_count,'answered',n,'pending_stump',pl.pending_stump,
    'reward',pl.reward_paid),'players',data,'server_now',clock_timestamp());
end $$;

