-- Lägg till radering av fristående meddelanden i Matteparkens Admin.
-- Kör efter supabase_personal_tasks_messages.sql.
-- Raderar INGA meddelanden vid installationen.
-- Endast den lärare som äger elevens klass får radera meddelandet.

create or replace function public.teacher_delete_direct_message(p_message_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_class_id uuid;
begin
  select m.class_id into v_class_id
  from public.teacher_direct_messages m
  where m.id = p_message_id;

  if v_class_id is null or auth.uid() is null
     or not public.matteparken_teacher_owns_class(v_class_id) then
    raise exception 'Access denied';
  end if;

  delete from public.teacher_direct_messages where id = p_message_id;
  return found;
end;
$$;

revoke all on function public.teacher_delete_direct_message(uuid) from public;
grant execute on function public.teacher_delete_direct_message(uuid) to authenticated;
