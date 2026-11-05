# Stack: Astro

For an Astro site or app, static or rendered on demand. Read with `node-tooling.md`, which covers the formatter, linter, test runners and scripts this builds on. General public guidance: the project's own choices in `AGENTS.md` come first.

Versions checked on 2026-11-06 against the npm registry and the Astro docs: Astro 7.4.7, `@astrojs/check` 0.9.12, `eslint-plugin-astro` 3.2.1, `prettier-plugin-astro` 1.1.2, with the Node tooling versions in `node-tooling.md`. `@astrojs/check` 0.9.12 lists TypeScript 5 or 6 as its peer, not 7: check that before upgrading TypeScript. Check again before relying on any of them: `npm view astro version`.

## Its docs

Astro runs a docs MCP server, `https://mcp.docs.astro.build/mcp`, which searches the current docs. Use it, or Context7, before writing code against an Astro API, and read the upgrade guide for the installed major version: APIs move between majors.

## The module shape

The shape from `conventions-code`, in `src/modules/<module>/`, with `src/pages/` holding only routes:

| Part | In Astro |
|---|---|
| contracts | Types and schemas other modules import |
| queries | Server-side reads, called from a page's frontmatter or an endpoint, never from a client island |
| actions | Astro Actions, defined with `defineAction()` and gathered into the `server` object in `src/actions/index.ts`. Each validates its `input` schema and checks permissions in its handler |
| tasks | Endpoints called by a scheduler, or the project's job runner |
| input | The schemas actions and endpoints accept, `accept: 'form'` for forms |
| rules | Plain TypeScript, no Astro imports, so unit tests run them directly |
| labels | The words for the module's values |
| ui | `.astro` components, and islands in the UI framework the project chose, only where the browser is needed |

- Pages stay thin: frontmatter calls queries, renders ui, and holds no logic of its own.
- Actions are public endpoints, reachable by name. Check who is calling in every handler and throw an `ActionError` when they may not, even when middleware also checks.
- A form calling an action needs that page rendered on demand, which needs an adapter.
- Content collections hold structured content. Their schema is its contract.

## Commands and scripts

`astro build` doesn't check types. `astro check`, from `@astrojs/check`, does, and is the stack's `typecheck`. Prettier needs `prettier-plugin-astro` to format `.astro` files, and ESLint `eslint-plugin-astro` to lint them.

```json
{
  "scripts": {
    "dev": "astro dev",
    "build": "astro build",
    "preview": "astro preview",
    "typecheck": "astro check"
  }
}
```

The rest of the scripts, `check` and `verify` included, are as in `node-tooling.md`.

## The project file

As `node-tooling.md`, with:

- `format`: `npm run format`, and `formatCheckStaged` rules for `*.astro`, `*.ts`, `*.css` and `*.md`, as in `{ "glob": "*.astro", "command": "npx prettier --check" }`.
- `check`: `npm run check`: format, lint, `astro check` and Vitest.
- `verify`: `npm run verify`: `check`, then Playwright against a build, and any database tests.
- `deadCode`: `npm run knip`. Knip has an Astro plugin that knows pages are entry points.
- `audit`: `npm audit --audit-level=high`.
- `testCommands`: `npm test`, `npm run test:e2e`, `npx vitest` and `npx playwright test`.

Astro has no database reset of its own. A database in the stack brings its own stack file and reset commands.

## End-to-end tests against a build

Test what people get. Build first, then let Playwright's `webServer` serve the build on a port of its own, so it never collides with the owner's `astro dev`. `webServer.url` and `use.baseURL` share that port. Point the build at the isolated test stack through its environment, never the owner's data. What serves the build depends on the setup, as Astro 7.4.7 checks:

- **A static build**, with every page prerendered, under any adapter or none: `npm run preview`.
- **On-demand pages, with an adapter that has a preview server**, as `@astrojs/node` and `@astrojs/cloudflare` do: `npm run preview` too. With the Node adapter in standalone mode, `PORT=<port> node ./dist/server/entry.mjs` also runs the built server.
- **On-demand pages with an adapter that has none**, such as `@astrojs/vercel` and `@astrojs/netlify`: `astro preview` exits with "adapter does not support the preview command". Use the adapter's own documented local server if it has one, or else run the tests against `astro dev` on its own port. That isn't the build, so it misses build-only failures and the host's behaviour: `verify` still runs `astro build`, and say in `AGENTS.md` that the end-to-end tests run against the dev server.

## With no database or sign-in

Many Astro sites are static content with no database and no one signing in. Then these can be skipped, and `AGENTS.md` should say they were:

- the isolated database stack, database tests and reset commands;
- the data-layer permission rules, access rules per table and the tests of them;
- actions, sessions and the sign-in parts of `/security-review`;
- an adapter, when every page is prerendered.

Everything else still holds: domain-first modules, `check` and `verify`, Playwright against the built site, screen checks and accessibility. Content collections still get schemas, and the rules that shape content still get unit tests.
