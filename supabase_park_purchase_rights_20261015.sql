-- Matteparken: auktoritativt register över KÖPTA rättigheter.
-- Enbart transaktioner i student_cone_purchases ger rättigheter.
-- Andra lokala dekorationer/belöningar behöver senare separat verifiering.
-- Existerande parker och saldon påverkas inte.

create table if not exists public.student_park_purchase_rights (
  purchase_id uuid primary key references public.student_cone_purchases(id),
  student_id uuid not null references public.students(id),
  purchase_kind text not null,
  item_id text not null default '',
  paid_price integer not null check (paid_price >= 0),
  purchased_at timestamptz not null,
  registered_at timestamptz not null default now(),
  constraint park_rights_purchase_kind_check
    check (purchase_kind in ('catalog','seedPack','decorBox','seasonal'))
);
create index if not exists student_park_purchase_rights_student_idx
  on public.student_park_purchase_rights(student_id,purchase_kind,item_id);
alter table public.student_park_purchase_rights enable row level security;
revoke all on public.student_park_purchase_rights from public,anon,authenticated;
grant select on public.student_park_purchase_rights to authenticated;
drop policy if exists student_park_purchase_rights_read_own
  on public.student_park_purchase_rights;
create policy student_park_purchase_rights_read_own
  on public.student_park_purchase_rights for select to authenticated
  using (student_id = (select private.current_student_id()));

-- Den här funktionen körs ENBART som databas-trigger, inte som exponerad RPC.
-- Ingen klient får själv registrera rätter eller skapa nya köp.
create or replace function private.register_student_park_purchase_right()
returns trigger
language plpgsql
security definer
set search_path = ''
as $body$
begin
  insert into public.student_park_purchase_rights
    (purchase_id,student_id,purchase_kind,item_id,paid_price,purchased_at)
  values (new.id,new.student_id,new.purchase_kind,coalesce(new.item_id,''),
          new.price,new.purchased_at)
  on conflict (purchase_id) do nothing;
  return new;
end;
$body$;

revoke all on function private.register_student_park_purchase_right() from public,anon,authenticated;

drop trigger if exists register_student_park_purchase_right_trigger
  on public.student_cone_purchases;
create trigger register_student_park_purchase_right_trigger
after insert on public.student_cone_purchases
for each row execute function private.register_student_park_purchase_right();

-- Backfyll med redan BETALDA historiska köp (lita inte på localStorage).
insert into public.student_park_purchase_rights
  (purchase_id,student_id,purchase_kind,item_id,paid_price,purchased_at)
select id,student_id,purchase_kind,coalesce(item_id,''),price,purchased_at
from public.student_cone_purchases
where purchase_kind in ('catalog','seedPack','decorBox','seasonal')
on conflict (purchase_id) do nothing;

comment on table public.student_park_purchase_rights is
  'Server-verified purchased catalog items and purchased box tokens only. Each row is backed by a real cone purchase. Box contents and free rewards require separate server validation. This table must not be writable by students.';
comment on table public.student_park_snapshots is
  'UNTRUSTED local park backups. Never consider a snapshot proof of ownership: a user can modify browser localStorage before uploading. Future canonical sync must validate against server-earned entitlements.';
