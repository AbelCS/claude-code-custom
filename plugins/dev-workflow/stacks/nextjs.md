# Stack: Next.js

For a Next.js app on the App Router. Read with `node-tooling.md`, which covers the formatter, linter, test runners and scripts this builds on. General public guidance: the project's own choices in `AGENTS.md` come first.

Versions checked on 2026-11-06 against the npm registry and the Next.js docs: Next.js 16.4.5, with the Node tooling versions in `node-tooling.md`. Check again before relying on them: `npm view next version`.

## Its docs ship with it

Next.js 16.2 and later ship docs matching the installed version in `node_modules/next/dist/docs/`. Read the guide there before writing code that uses a Next.js API, then Context7 for anything it doesn't cover. Upgrading Next.js upgrades these docs too.

From 16.3, `next dev` writes a block of its own into `AGENTS.md`, between `<!-- BEGIN:nextjs-agent-rules -->` and `<!-- END:nextjs-agent-rules -->`, pointing agents at those docs. It sits outside dev-workflow's managed sections, so `setup` leaves it alone. Commit it with the work rather than deleting it, as `next dev` writes it again. The `agentRules` option in `next.config` turns it off.

## The module shape

The shape from `conventions-code`, in `src/modules/<module>/`, with `app/` holding only routes:

| Part | In Next.js |
|---|---|
| contracts | Types and schemas other modules import |
| queries | Server-only reads, starting with `import 'server-only'`, called from Server Components |
| actions | Server Functions, in files starting with `'use server'`. Each parses its input, checks permissions and saves on the server |
| tasks | Route handlers called by a scheduler, or the project's job runner |
| input | Schemas for form data and search params, used by actions and pages |
| rules | Plain TypeScript, no Next.js imports, so unit tests run them directly |
| labels | The words for the module's values |
| ui | Server Components by default. `'use client'` only on the parts that need the browser |

- Routes stay thin: `page.tsx`, `layout.tsx` and `route.ts` call queries and actions and render ui, with no logic of their own.
- `server-only` makes importing a query into client code a build error. That holds the "ui never reads the database" boundary at build time, next to the lint rules in `node-tooling.md`.
- Every page gets its own `loading.tsx`, as its loading skeleton.
- Validate in every Server Function, even one called only from a form: it is a public endpoint.

## Commands and scripts

`next lint` is gone since 16. Lint with the ESLint CLI and `eslint-config-next`; the `next-lint-to-eslint-cli` codemod moves an older project over. Type checks need the route types first: `next typegen && tsc --noEmit`.

```json
{
  "scripts": {
    "dev": "next dev",
    "build": "next build",
    "start": "next start",
    "typecheck": "next typegen && tsc --noEmit"
  }
}
```

The rest of the scripts, `check` and `verify` included, are as in `node-tooling.md`.

## The project file

As `node-tooling.md`, with:

- `format`: `npm run format`, and `formatCheckStaged` rules for `*.ts`, `*.tsx`, `*.css` and `*.md`.
- `check`: `npm run check`: format, lint, `typecheck` and Vitest.
- `verify`: `npm run verify`: `check`, then Playwright against a build, and any database tests.
- `deadCode`: `npm run knip`. Knip has a Next.js plugin that knows the route files are entry points.
- `audit`: `npm audit --audit-level=high`.
- `testCommands`: `npm test`, `npm run test:e2e`, `npx vitest` and `npx playwright test`.

Next.js has no database reset of its own. A database in the stack brings its own stack file and reset commands.

## End-to-end tests against a build

People use the built app, so test that. In `playwright.config.ts`, `webServer.command` builds and starts it, `npm run build && npm run start`, on a port of its own, so it never collides with the owner's `next dev`, and with `reuseExistingServer` off. `webServer.url` and `use.baseURL` share that port. Point the build at the isolated test stack through its environment, never the owner's data.

Vitest can't render async Server Components, so cover those through Playwright. Vitest covers rules, input schemas and synchronous components.
