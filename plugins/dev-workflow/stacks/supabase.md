# Stack: Supabase

For a project whose database, sign-in or storage is Supabase, worked on locally through the Supabase CLI. Read with the app's own stack files. General public guidance: the project's own choices in `AGENTS.md` come first.

Versions checked on 2026-11-06 against the CLI's releases and the Supabase docs: Supabase CLI 3.0.0, as the `supabase` npm package. v3 is a major release: commands target the local stack by default, `--remote` replaces `--linked`, `--project-ref` and `--db-url`, and every change to a hosted project asks first, or needs `--yes`. Read its migration guide before upgrading from v2. Check again before relying on it: `npm view supabase version`.

## Row-level security is the data layer

`conventions-code` enforces permissions in the data layer as well as in code. Here that layer is Postgres row-level security:

- Every table in an exposed schema gets row-level security turned on, and its policies, in the migration that creates it. A table without policies refuses every row, which is safe but easy to miss in a test.
- Grants decide who may try, and policies which rows. Test both: a missing grant or a failed `with check` raises `42501`, while a `using` clause just matches no rows.
- The secret key bypasses row-level security. It lives only on the server, never in the browser and never in a query that acts for a person.
- Code still checks permissions too, for clear errors. The policies make sure a missed check can't leak or change a row.

## Its test tools

- **Policies:** pgTAP files in `supabase/tests/`, made with `supabase test new <table>_rls` and run against the test stack, never a bare `supabase test db`, which tests the default local stack: see below. One file per table, testing each role: `anon`, a signed-in owner and a signed-in stranger, through `set local role` and `request.jwt.claim.sub`. Pair every denied write with a read proving the row is intact. Each file runs in a transaction that rolls back.
- **Helpers:** `basejump-supabase_test_helpers` adds `tests.create_supabase_user()`, `tests.authenticate_as()` and `tests.rls_enabled()`. The docs' advanced pgTAP guide installs it in a setup file run first.
- **Complex reads:** tests through `supabase-js` against the test stack, signed in as a real test user, so they go through the same policies people do.

## An isolated test stack

Tests never touch the owner's local data. Give them a stack of their own, reset before each run:

- With the CLI's stack commands, experimental since 2.119.0: `[experimental] stack = true` in `supabase/config.toml` and no fixed ports, then `supabase start --stack test` beside `supabase start --stack dev`. `supabase status --stack test --env` gives its URLs and keys. Database commands take no `--stack`, and without a target they reach the default stack, so name the test stack through its database URL: `supabase db reset --remote=<its DB_URL> --yes`, then `supabase test db --remote=<its DB_URL> --yes`. v3 counts that URL as a remote, so `--yes` lets them run unattended. `--remote=<url>` replaces v2's `--db-url`, which still works with a warning until v4.
- Without them, a second project folder with its own `project_id` and ports, every command naming it: `supabase db reset --workdir <folder>` and `supabase test db --workdir <folder>`.

Put the reset and the run in one script, such as `scripts/test-db`, that resets only the test stack. The hooks hold a reset typed in a session for a person's yes, but not one inside that script. Suites sharing the test stack don't run at the same time.

## Reset commands

These wipe a database. `supabase.resets`, next to this file, lists them for `databaseResetCommands`, and `setup` adds them to the project file: `supabase db reset`, `supabase migration down`, `supabase stop --no-backup` and `supabase stack destroy`, each also through `npx`, and each matching its targeted forms too, such as `--remote=<url>` or `--workdir <folder>`. A project running the CLI another way, such as `pnpm exec supabase`, adds that form as its own. Never reset the owner's local database without asking.

## A read-only database MCP

The local stack serves Supabase's MCP server at `http://localhost:54321/mcp`, or the URL `supabase status` gives with the stack commands on. Connect it to the local stack only, never a hosted project, with `?read_only=true`, which runs every query as a read-only Postgres user. The docs describe that parameter for the hosted server: check that a write is refused before relying on it locally.

## The module shape

The shape from `conventions-code`, with Supabase as the database:

| Part | With Supabase |
|---|---|
| contracts | Types generated from the schema, `supabase gen types typescript`, which v3 reads from the local stack by default, plus the module's own types |
| queries | `supabase-js` selects, or SQL views and functions for complex reads. Never in ui |
| actions | Server code calling `supabase-js` as the signed-in person, so policies apply |
| tasks | Scheduled or background work: edge functions, or database jobs |
| input | Schemas checked on the server before any write |
| rules | Plain TypeScript, or SQL functions when the database must enforce them too |
| labels, ui | As the app's stack file says |

- **Every row:** the API stops at `max_rows`, 1000 by default in `[api]` of `config.toml`, without an error. Page by a unique key, ordering by it and filtering past the last one seen, rather than `range()` offsets.
- **All or nothing:** `supabase-js` has no transactions. A save that changes several rows is one Postgres function, called with `rpc()`.
- **Migrations only:** `supabase migration new <name>`, or `supabase db diff` to draft one, reviewed before committing. Never change the schema through the dashboard.

## The project file

The app's stack file gives most commands. Supabase adds:

- `format`: SQL formatting, if the project has a formatter for it.
- `check`: unchanged. It needs no database, so it stays fast.
- `verify`: also runs `scripts/test-db`: the test stack reset, `supabase test db` with the test stack's `--remote=<its DB_URL> --yes` or `--workdir`, and the database tests.
- `deadCode` and `audit`: unchanged, from the app's stack file.
- `testCommands`: add `supabase test db` and `npx supabase test db`, which match their longer forms too, and the test stack script.
- `databaseResetCommands`: comes from `supabase.resets`. Add only the project's own.
