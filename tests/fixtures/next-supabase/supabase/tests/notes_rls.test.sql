-- Row-level security on public.notes, as a signed-in person.
begin;
create extension if not exists pgtap with schema extensions;
select plan(3);

insert into public.notes (owner, body) values
  ('11111111-1111-1111-1111-111111111111', 'mine'),
  ('22222222-2222-2222-2222-222222222222', 'theirs');

-- Signed in as the first person. auth.uid() reads claim.sub, and with Supabase Auth
-- running, claims as well, so both are set.
set local role authenticated;
set local request.jwt.claim.sub to '11111111-1111-1111-1111-111111111111';
set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';

select results_eq(
  'select body from public.notes',
  $$ values ('mine') $$,
  'a person sees only their own notes'
);

select lives_ok(
  $$ insert into public.notes (body) values ('new') $$,
  'a person can add a note of their own'
);

select throws_ok(
  $$ insert into public.notes (owner, body) values ('22222222-2222-2222-2222-222222222222', 'forged') $$,
  '42501',
  null,
  'a person cannot add a note as someone else'
);

select * from finish();
rollback;
