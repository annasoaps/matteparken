-- Matteparken: server-owned catalogue items (phase 1: schema and RPC only).
-- Each catalogue asset is backed by exactly one paid purchase.
-- Never import client-created placements as ownership proof.

create table if not exists public.student_park_catalog_assets (
  purchase_id uuid primary key
    references public.student_park_purchase_rights(purchase_id),
  student_id uuid not null references public.students(id),
  item_id text not null,
  zone text,
  x numeric,
  y numeric,
  updated_at timestamptz not null default now(),
  constraint student_park_catalog_assets_location_check check (
    (zone is null and x is null and y is null)
    or (zone in ('southwest','northwest','northeast','southeast')
        and x between 0 and 100 and y between 0 and 100)
  )
);

create index if not exists student_park_catalog_assets_student_idx
  on public.student_park_catalog_assets(student_id, item_id);
alter table public.student_park_catalog_assets enable row level security;
revoke all on public.student_park_catalog_assets from public,anon,authenticated;
grant select on public.student_park_catalog_assets to authenticated;
drop policy if exists student_park_catalog_assets_read_own
  on public.student_park_catalog_assets;
create policy student_park_catalog_assets_read_own
  on public.student_park_catalog_assets for select to authenticated
  using (student_id = (select private.current_student_id()));

create or replace function private.grant_student_catalog_asset()
returns trigger language plpgsql security definer set search_path = ''
as $body$
begin
  if new.purchase_kind='catalog' then
    insert into public.student_park_catalog_assets
      (purchase_id,student_id,item_id)
    values(new.purchase_id,new.student_id,new.item_id)
    on conflict(purchase_id) do nothing;
  end if;
  return new;
end;
$body$;

revoke all on function private.grant_student_catalog_asset() from public,anon,authenticated;
drop trigger if exists grant_student_catalog_asset_trigger
  on public.student_park_purchase_rights;
create trigger grant_student_catalog_asset_trigger
after insert on public.student_park_purchase_rights
for each row execute function private.grant_student_catalog_asset();

-- Historiska betalda katalogföremål får egna ID:n, men ingen påhittad position.
insert into public.student_park_catalog_assets
  (purchase_id,student_id,item_id)
select purchase_id,student_id,item_id
from public.student_park_purchase_rights
where purchase_kind='catalog'
on conflict(purchase_id) do nothing;

-- Enda skrivvägen för att placera ett serverägt katalogföremål.
create or replace function public.student_place_verified_catalog_asset(
  p_purchase_id uuid,
  p_zone text default null,
  p_x numeric default null,
  p_y numeric default null
)
returns jsonb
language plpgsql security definer set search_path = ''
as $body$
declare
  v_student uuid := private.current_student_id();
  v_item text;
  v_allowed_zone text;
begin
  if v_student is null then
    return jsonb_build_object('ok',false,'reason','no_student_session');
  end if;
  select item_id into v_item
  from public.student_park_catalog_assets
  where purchase_id=p_purchase_id and student_id=v_student
  for update;
  if not found then
    return jsonb_build_object('ok',false,'reason','not_owned');
  end if;
  v_allowed_zone := case
    when v_item in ('flowerShrub','bench','birdhouse') then 'southwest'
    when v_item in ('mushroomBasket','birch','spruce','pine','oak') then 'northwest'
    when v_item='miniJetty' then 'southeast'
    else null
  end;
  if v_allowed_zone is null then
    return jsonb_build_object('ok',false,'reason','invalid_item');
  end if;
  if p_zone is not null then
    if p_zone <> v_allowed_zone or p_x is null or p_y is null
       or p_x < 0 or p_x > 100 or p_y < 0 or p_y > 100 then
      return jsonb_build_object('ok',false,'reason','invalid_location');
    end if;
    update public.student_park_catalog_assets
       set zone=p_zone,x=round(p_x,4),y=round(p_y,4),updated_at=now()
     where purchase_id=p_purchase_id;
  else
    update public.student_park_catalog_assets
       set zone=null,x=null,y=null,updated_at=now()
     where purchase_id=p_purchase_id;
  end if;
  return jsonb_build_object('ok',true,'purchase_id',p_purchase_id,
    'item_id',v_item,'zone',p_zone,
    'x',case when p_zone is null then null else round(p_x,4) end,
    'y',case when p_zone is null then null else round(p_y,4) end);
end;
$body$;

revoke all on function public.student_place_verified_catalog_asset(uuid,text,numeric,numeric)
  from public,anon,authenticated;
grant execute on function public.student_place_verified_catalog_asset(uuid,text,numeric,numeric)
  to authenticated;

comment on table public.student_park_catalog_assets is
  'Verified catalogue items. One asset per paid catalogue purchase. Coordinates may be modified ONLY through ownership-checking RPC. Existing local parks are not automatically imported.';