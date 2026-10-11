-- Matteparken: privata läraranteckningar för elevkoder.
-- Kör i Supabase SQL Editor en gång. Inga elevkonton får läsa tabellen direkt.
create table if not exists public.teacher_student_notes (
  student_id uuid primary key references public.students(id) on delete cascade,
  note text not null default '',
  updated_at timestamptz not null default now(),
  constraint teacher_student_note_length check (char_length(note) <= 80)
);
alter table public.teacher_student_notes enable row level security;
revoke all on public.teacher_student_notes from anon, authenticated;
-- Only owner/assigned teacher to the student's class can read notes.
create or replace function public.teacher_list_student_notes(p_class_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_notes jsonb;
begin
  if not public.matteparken_teacher_owns_class(p_class_id) then
    raise exception 'Access denied';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('student_id',n.student_id,'note',n.note)),'[]'::jsonb)
    into v_notes
    from public.teacher_student_notes n
    join public.students s on s.id=n.student_id
    where s.class_id=p_class_id;
  return v_notes;
end;
$$;
create or replace function public.teacher_set_student_note(p_student_id uuid,p_note text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_class_id uuid; v_note text;
begin
  select s.class_id into v_class_id from public.students s where s.id=p_student_id;
  if v_class_id is null or not public.matteparken_teacher_owns_class(v_class_id) then
    raise exception 'Access denied';
  end if;
  v_note:=trim(coalesce(p_note,''));
  if char_length(v_note)>80 then
    return jsonb_build_object('ok',false,'reason','too_long');
  end if;
  if v_note='' then
    delete from public.teacher_student_notes where student_id=p_student_id;
  else
    insert into public.teacher_student_notes(student_id,note,updated_at)
    values(p_student_id,v_note,now())
    on conflict(student_id) do update set note=excluded.note,updated_at=now();
  end if;
  return jsonb_build_object('ok',true);
end;
$$;
revoke all on function public.teacher_list_student_notes(uuid) from public;
revoke all on function public.teacher_set_student_note(uuid,text) from public;
grant execute on function public.teacher_list_student_notes(uuid) to authenticated;
grant execute on function public.teacher_set_student_note(uuid,text) to authenticated;
