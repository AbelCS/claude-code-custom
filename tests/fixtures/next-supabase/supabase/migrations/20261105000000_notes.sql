-- Each person's notes, which only they can read or write.
create table public.notes (
  id bigint generated always as identity primary key,
  owner uuid not null default auth.uid(),
  body text not null
);

alter table public.notes enable row level security;

create policy "people read their own notes" on public.notes
  for select to authenticated using (owner = (select auth.uid()));

create policy "people write their own notes" on public.notes
  for insert to authenticated with check (owner = (select auth.uid()));

grant select, insert on public.notes to authenticated;
