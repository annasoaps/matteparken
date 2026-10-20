-- Arkivera redeem-koder utan att radera elevens inlösningshistorik.
-- Koderna försvinner från lärarens lista och kan inte aktiveras igen.
-- Den unika kodsträngen reserveras fortsatt, så gamla koder inte kan återanvändas.

alter table public.redeem_codes
  add column if not exists archived_at timestamptz;

comment on column public.redeem_codes.archived_at is
  'Tid då läraren tog bort (arkiverade) koden i Admin. Behåll inlösningar och belöningar.';

-- Ett arkiverat erbjudande får aldrig aktiveras igen.
alter table public.redeem_codes
  add constraint redeem_codes_archived_disabled_check
  check (archived_at is null or enabled = false);

create or replace function public.teacher_archive_redeem_code(p_code_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_class_id uuid;
begin
  select r.class_id into v_class_id
  from public.redeem_codes r
  where r.id = p_code_id;

  if v_class_id is null then
    return jsonb_build_object('ok',false,'reason','not_found');
  end if;

  if not public.matteparken_teacher_owns_class(v_class_id) then
    return jsonb_build_object('ok',false,'reason','forbidden');
  end if;

  update public.redeem_codes
    set enabled = false,
        archived_at = now()
  where id = p_code_id
    and archived_at is null;

  if not found then
    return jsonb_build_object('ok',false,'reason','already_archived');
  end if;

  return jsonb_build_object('ok',true);
end;
$$;

revoke all on function public.teacher_archive_redeem_code(uuid) from public, anon;
grant execute on function public.teacher_archive_redeem_code(uuid) to authenticated;

-- Nuvarande Admin-anrop använder samma funktionsnamn, men visar bara
-- koder som ännu inte arkiverats. Historiken i redeem_redemptions rörs inte.
create or replace function public.teacher_list_redeem_codes(p_class_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
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
  where r.class_id=p_class_id
    and r.archived_at is null;

  return jsonb_build_object('ok',true,'codes',v_result);
end;
$$;
