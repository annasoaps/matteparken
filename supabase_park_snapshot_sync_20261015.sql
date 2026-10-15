-- Automatic park snapshots pilot. Existing snapshots and local parks stay unchanged.
-- The snapshots are UNTRUSTED backups, never ownership grants.
-- Appends are serialized per student and only succeed if the caller has
-- observed the latest prior snapshot (optimistic concurrency control).
create or replace function public.student_append_park_snapshot(
  p_snapshot jsonb,
  p_expected_latest_id uuid default null
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $body$
declare
  v_student uuid := private.current_student_id();
  v_latest_id uuid;
  v_latest_snapshot jsonb;
  v_new_id uuid;
begin
  if v_student is null then
    return jsonb_build_object('ok',false,'reason','no_student_session');
  end if;
  if p_snapshot is null
    or jsonb_typeof(p_snapshot) <> 'object'
    or p_snapshot->>'format' <> 'matteparken-localstorage-v1'
    or jsonb_typeof(p_snapshot->'values') <> 'object'
    or not (p_snapshot->'values' ? 'parkItems')
    or not (p_snapshot->'values' ? 'onboarding')
    or octet_length(p_snapshot::text) > 2097152
  then
    return jsonb_build_object('ok',false,'reason','invalid_snapshot');
  end if;

  perform pg_advisory_xact_lock(26015, hashtext(v_student::text));
  select id,snapshot into v_latest_id,v_latest_snapshot
    from public.student_park_snapshots
   where student_id=v_student
   order by saved_at desc,id desc
   limit 1;

  if v_latest_id is distinct from p_expected_latest_id then
    return jsonb_build_object('ok',false,'reason','newer_cloud_version',
      'latest_id',v_latest_id);
  end if;

  if v_latest_id is not null
    and v_latest_snapshot->'values' = p_snapshot->'values' then
    return jsonb_build_object('ok',true,'unchanged',true,'id',v_latest_id);
  end if;

  insert into public.student_park_snapshots(student_id,snapshot,schema_version)
    values (v_student,p_snapshot,1)
    returning id into v_new_id;
  return jsonb_build_object('ok',true,'unchanged',false,'id',v_new_id);
end;
$body$;

revoke all on function public.student_append_park_snapshot(jsonb,uuid) from public,anon,authenticated;
grant execute on function public.student_append_park_snapshot(jsonb,uuid) to authenticated;
comment on function public.student_append_park_snapshot(jsonb,uuid) is
  'Append untrusted local park backup only if cloud head has not changed. Does not certify ownership or alter existing parks.';