-- Matteparken: återkommande låsta läxtider per klass (svensk tid).
-- Kör denna SQL i Supabase innan uppdaterade admin.html/index.html publiceras.
-- Existerande klasser behåller den tidigare spärren mån–fre 08.20–14.00
-- tills en lärare sparar ett eget veckoschema. En tom lista = aldrig låst.

alter table public.classes
  add column if not exists homework_blocked_times jsonb not null
  default '[
    {"day":1,"start":"08:20","end":"14:00"},
    {"day":2,"start":"08:20","end":"14:00"},
    {"day":3,"start":"08:20","end":"14:00"},
    {"day":4,"start":"08:20","end":"14:00"},
    {"day":5,"start":"08:20","end":"14:00"}
  ]'::jsonb;

comment on column public.classes.homework_blocked_times is
  'Veckovisa läxspärrar i Europe/Stockholm. day=ISO-veckodag 1–7; start inklusive, end exklusive.';

create or replace function public.teacher_set_homework_blocked_times(
  p_class_id uuid, p_windows jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  slot jsonb;
  start_minutes integer;
  end_minutes integer;
begin
  if not private.is_teacher_for_class(p_class_id) then
    return jsonb_build_object('ok',false,'reason','forbidden');
  end if;

  if p_windows is null or jsonb_typeof(p_windows) <> 'array' then
    return jsonb_build_object('ok',false,'reason','invalid_schedule');
  end if;
  if jsonb_array_length(p_windows) > 40 then
    return jsonb_build_object('ok',false,'reason','too_many_windows');
  end if;

  for slot in select value from jsonb_array_elements(p_windows) loop
    if jsonb_typeof(slot) <> 'object'
       or coalesce(slot->>'day','') !~ '^[1-7]$'
       or coalesce(slot->>'start','') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
       or coalesce(slot->>'end','') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then
      return jsonb_build_object('ok',false,'reason','invalid_window');
    end if;
    start_minutes := split_part(slot->>'start',':',1)::int * 60 + split_part(slot->>'start',':',2)::int;
    end_minutes := split_part(slot->>'end',':',1)::int * 60 + split_part(slot->>'end',':',2)::int;
    if start_minutes >= end_minutes then
      return jsonb_build_object('ok',false,'reason','invalid_window');
    end if;
  end loop;

  update public.classes
     set homework_blocked_times = p_windows
   where id = p_class_id;
  if not found then
    return jsonb_build_object('ok',false,'reason','class_not_found');
  end if;
  return jsonb_build_object('ok',true,'windows',p_windows);
end;
$$;

revoke all on function public.teacher_set_homework_blocked_times(uuid,jsonb) from public, anon;
grant execute on function public.teacher_set_homework_blocked_times(uuid,jsonb) to authenticated;

-- Spärren kontrolleras också på servern. Att ändra datorns klocka,
-- behålla en spelruta öppen eller anropa RPC direkt ska inte markera läxan klar.
-- Påverkar enbart när en läxuppgift går från ofärdig till färdig.
create or replace function private.prevent_locked_homework_completion()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_class_id uuid;
  v_windows jsonb;
  v_local_time timestamp;
  v_day integer;
  v_minute integer;
begin
  if coalesce(new.completed,0) < 1 then return new; end if;
  if tg_op = 'UPDATE' then
    if coalesce(old.completed,0) >= 1 then return new; end if;
  end if;

  select a.class_id into v_class_id
    from public.assignments a
   where a.id = new.assignment_id
     and a.homework_id is not null;
  if v_class_id is null then return new; end if;

  select c.homework_blocked_times into v_windows
    from public.classes c
   where c.id = v_class_id;
  if v_windows is null then return new; end if;

  v_local_time := now() at time zone 'Europe/Stockholm';
  v_day := extract(isodow from v_local_time)::integer;
  v_minute := extract(hour from v_local_time)::integer * 60
           + extract(minute from v_local_time)::integer;

  if exists (
    select 1
      from jsonb_array_elements(v_windows) slot
     where (slot->>'day')::integer = v_day
       and v_minute >= split_part(slot->>'start',':',1)::integer * 60
                       + split_part(slot->>'start',':',2)::integer
       and v_minute <  split_part(slot->>'end',':',1)::integer * 60
                       + split_part(slot->>'end',':',2)::integer
  ) then
    raise exception 'homework_locked' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_prevent_locked_homework_completion on public.student_assignment_progress;
create trigger trg_prevent_locked_homework_completion
  before insert or update of completed on public.student_assignment_progress
  for each row execute function private.prevent_locked_homework_completion();
