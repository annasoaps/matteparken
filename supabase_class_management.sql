-- Matteparken: class management for teacher admin
-- Run once in Supabase SQL Editor.
-- Adds rename/archive/restore/delete RPCs used by admin.html.

alter table public.classes
  add column if not exists archived boolean not null default false;

-- Helper: verify that the authenticated user is linked to a class.
-- Supports the common teacher id column names used by earlier Matteparken versions.
create or replace function public.matteparken_teacher_owns_class(p_class_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_col text;
  v_ok boolean := false;
begin
  if v_uid is null then
    return false;
  end if;

  select c.column_name
    into v_col
  from information_schema.columns c
  where c.table_schema = 'public'
    and c.table_name = 'teacher_classes'
    and c.column_name in ('teacher_id','user_id','auth_user_id')
  order by case c.column_name
    when 'teacher_id' then 1
    when 'user_id' then 2
    when 'auth_user_id' then 3
    else 99
  end
  limit 1;

  if v_col is null then
    raise exception 'Could not find teacher identity column in public.teacher_classes';
  end if;

  execute format(
    'select exists (
       select 1
       from public.teacher_classes
       where class_id = $1 and %I = $2
     )',
    v_col
  )
  into v_ok
  using p_class_id, v_uid;

  return coalesce(v_ok,false);
end;
$$;

revoke all on function public.matteparken_teacher_owns_class(uuid) from public;
grant execute on function public.matteparken_teacher_owns_class(uuid) to authenticated;

create or replace function public.teacher_update_class(
  p_class_id uuid,
  p_code text,
  p_name text default ''
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text := upper(trim(coalesce(p_code,'')));
  v_name text := trim(coalesce(p_name,''));
begin
  if not public.matteparken_teacher_owns_class(p_class_id) then
    return jsonb_build_object('ok',false,'reason','forbidden');
  end if;

  if v_code = '' or length(v_code) > 20 then
    return jsonb_build_object('ok',false,'reason','invalid_code');
  end if;

  if length(v_name) > 80 then
    return jsonb_build_object('ok',false,'reason','invalid_name');
  end if;

  update public.classes
     set code = v_code,
         name = nullif(v_name,'')
   where id = p_class_id;

  return jsonb_build_object('ok',true,'class_id',p_class_id,'code',v_code,'name',v_name);
exception
  when unique_violation then
    return jsonb_build_object('ok',false,'reason','class_exists');
end;
$$;

revoke all on function public.teacher_update_class(uuid,text,text) from public;
grant execute on function public.teacher_update_class(uuid,text,text) to authenticated;

create or replace function public.teacher_set_class_archived(
  p_class_id uuid,
  p_archived boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.matteparken_teacher_owns_class(p_class_id) then
    return jsonb_build_object('ok',false,'reason','forbidden');
  end if;

  update public.classes
     set archived = coalesce(p_archived,false)
   where id = p_class_id;

  return jsonb_build_object('ok',true,'class_id',p_class_id,'archived',coalesce(p_archived,false));
end;
$$;

revoke all on function public.teacher_set_class_archived(uuid,boolean) from public;
grant execute on function public.teacher_set_class_archived(uuid,boolean) to authenticated;

create or replace function public.teacher_delete_class(p_class_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_archived boolean;
  v_uid uuid := auth.uid();
  v_col text;
begin
  if not public.matteparken_teacher_owns_class(p_class_id) then
    return jsonb_build_object('ok',false,'reason','forbidden');
  end if;

  select archived into v_archived
  from public.classes
  where id = p_class_id;

  if coalesce(v_archived,false) = false then
    return jsonb_build_object('ok',false,'reason','archive_first');
  end if;

  select c.column_name
    into v_col
  from information_schema.columns c
  where c.table_schema = 'public'
    and c.table_name = 'teacher_classes'
    and c.column_name in ('teacher_id','user_id','auth_user_id')
  order by case c.column_name
    when 'teacher_id' then 1
    when 'user_id' then 2
    when 'auth_user_id' then 3
    else 99
  end
  limit 1;

  if v_col is null then
    return jsonb_build_object('ok',false,'reason','teacher_identity_column_missing');
  end if;

  -- Remove only the current teacher's link. If the class is shared with another
  -- teacher, or if related class data prevents deletion, the exception block
  -- rolls this statement back as part of the same subtransaction.
  execute format(
    'delete from public.teacher_classes where class_id = $1 and %I = $2',
    v_col
  )
  using p_class_id, v_uid;

  delete from public.classes
   where id = p_class_id;

  return jsonb_build_object('ok',true,'class_id',p_class_id);
exception
  when foreign_key_violation then
    return jsonb_build_object('ok',false,'reason','class_has_data');
end;
$;

revoke all on function public.teacher_delete_class(uuid) from public;
grant execute on function public.teacher_delete_class(uuid) to authenticated;

comment on column public.classes.archived is
  'Archived classes are hidden from the normal teacher class selector but retain their data.';
