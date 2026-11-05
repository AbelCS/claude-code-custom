# Stack: Node tooling

For any project whose code and tools run on Node and npm, whatever its framework. Read with the framework's own stack file, if it has one. General public guidance: the project's own choices in `AGENTS.md` come first.

Versions checked on 2026-11-06 against the npm registry and each tool's docs: Node 26.13.0 (the current LTS line), npm 12.2.2, TypeScript 7.0.2, ESLint 10.14.0, typescript-eslint 8.72.1, Prettier 3.9.10, Vitest 5.1.0, Playwright 1.65.0, Knip 6.44.1. Check again before relying on them: `npm view <package> version`.

## Read the docs that shipped first

The installed version's own docs beat anything remembered. Before writing code against a package, look in `node_modules/<package>/` for a `docs/` folder, an `AGENTS.md`, an `llms.txt` or a README, which match the installed version. Then Context7. Never write from memory against a major version you haven't read about.

## The tools

| Job | Tool | Notes |
|---|---|---|
| Formatter | Prettier | `--cache`, so a run checks only what changed |
| Linter | ESLint, flat config, with typescript-eslint | `--cache`. Boundaries as lint errors, below |
| Types | TypeScript, `tsc --noEmit` | Strict mode on |
| Unit tests | Vitest | `vitest run` in scripts, so it never waits in watch mode |
| End-to-end tests | Playwright | Against a production build, on its own isolated stack |
| Dead code | Knip | Unused files, exports and dependencies |
| Audit | `npm audit` | `--audit-level=high` keeps it to what matters |

pnpm, Yarn and Bun work the same way with their own commands. Use the one the lockfile shows, and never mix two.

## Scripts

Fast checks first, so `check` stays quick enough for every push:

```json
{
  "scripts": {
    "format": "prettier --write --cache .",
    "format:check": "prettier --check --cache .",
    "lint": "eslint --cache .",
    "typecheck": "tsc --noEmit",
    "test": "vitest run",
    "test:e2e": "playwright test",
    "check": "npm run format:check && npm run lint && npm run typecheck && npm test",
    "verify": "npm run check && npm run test:e2e",
    "knip": "knip"
  }
}
```

`check` is format, lint, types and unit tests. `verify` adds the database and end-to-end tests. Keep the caches out of git: Prettier's and ESLint's sit in `node_modules/.cache/` and `.eslintcache`.

`setup` adds a `prepare` script that turns the git hooks on, so `npm install` does it in a fresh clone. Keep it when editing scripts.

## The project file

How this stack fills `.claude/dev-workflow.json`:

- `format`: `npm run format`.
- `formatCheckStaged`: one rule per glob, each only checking, such as `{ "glob": "*.ts", "command": "npx prettier --check --ignore-unknown" }`, and the same for `*.tsx`, `*.js`, `*.json`, `*.css` and `*.md` as the project has them.
- `check`: `npm run check`. Required, as `pre-push` runs it.
- `verify`: `npm run verify`.
- `deadCode`: `npm run knip`.
- `audit`: `npm audit --audit-level=high`.
- `testCommands`: `npm test`, `npm run test:e2e`, `npx vitest` and `npx playwright test`, plus any other way the project runs its tests.

## The module shape

The shape from `conventions-code`, one folder per module, such as `src/modules/<module>/` holding contracts, queries, actions, tasks, input, rules, labels and ui, each a file or a folder as it grows. Name the folders after the domain, as in the glossary.

Boundaries are ESLint errors, not review comments:

- Each module is imported only through its contracts. `eslint-plugin-boundaries`, or `no-restricted-imports` with patterns, can say that a path outside the module may import only `<module>/contracts`.
- Modules depend downwards: give each layer the layers it may import, and make the rest an error.
- ui never imports a database client. Ban the client's package in ui files with `no-restricted-imports`.

If the linter can't express a boundary yet, add the rule that can, and say so.

## Tests

- Vitest for rules and the pure functions that shape data: fast, with no network or database.
- Database tests against a real database, signed in as a real role, on the isolated test stack.
- Playwright against a production build, as people get it, with its `webServer` starting the built app. Its own isolated stack, reset before each run. Suites sharing a stack don't run at the same time: set `workers` and Vitest's `fileParallelism` to match.

## Upgrades

`npm outdated` lists what's behind. Verify the latest stable with `npm view <package> version`, read the migration guide before a major upgrade, upgrade one major at a time, and run `verify` after each.
