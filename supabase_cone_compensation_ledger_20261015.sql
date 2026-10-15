-- Matteparken: bokföring för manuella kottkompensationer.
-- Endast behörig databasadministration får registrera en kompensation.
-- Källköpets id är unikt för att samma extraköp aldrig krediteras två gånger.
create table if not exists public.student_cone_compensations (
  source_purchase_id uuid primary key
    references public.student_cone_purchases(id),
  student_id uuid not null references public.students(id),
  amount integer not null check (amount > 0),
  batch_key text not null,
  reason text not null,
  compensated_at timestamptz not null default now()
);
create index if not exists student_cone_compensations_student_idx
  on public.student_cone_compensations(student_id,compensated_at desc);

alter table public.student_cone_compensations enable row level security;
revoke all on public.student_cone_compensations from public,anon,authenticated;
comment on table public.student_cone_compensations is
  'Administrator-created one-time goodwill cone compensation ledger. No client write permissions. Each entry refers to a real prior purchase.';

