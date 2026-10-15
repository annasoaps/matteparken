-- Matteparken park snapshots: phase 1, append-only and non-destructive.
-- This stores copies of existing browser data but NEVER restores or overwrites local parks.
create table if not exists public.student_park_snapshots (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null default private.current_student_id()
    references public.students(id),
  snapshot jsonb not null,
  schema_version integer not null default 1
    check (schema_version = 1),
  saved_at timestamptz not null default now(),
  constraint student_park_snapshots_json_object check (
    jsonb_typeof(snapshot) = 'object'
  ),
  constraint student_park_snapshots_max_size check (
    octet_length(snapshot::text) <= 2097152
  )
);
alter table public.student_park_snapshots enable row level security;
create index if not exists student_park_snapshots_student_date_idx
  on public.student_park_snapshots(student_id, saved_at desc);

revoke all on table public.student_park_snapshots from public, anon, authenticated;
grant select, insert on table public.student_park_snapshots to authenticated;

drop policy if exists student_park_snapshots_read_own
  on public.student_park_snapshots;
create policy student_park_snapshots_read_own
  on public.student_park_snapshots for select to authenticated
  using (student_id = (select private.current_student_id()));

drop policy if exists student_park_snapshots_insert_own
  on public.student_park_snapshots;
create policy student_park_snapshots_insert_own
  on public.student_park_snapshots for insert to authenticated
  with check (student_id = (select private.current_student_id()));

comment on table public.student_park_snapshots is
  'Append-only backup copies of local Matteparken parks. Do not use as canonical state until explicitly migrated.';