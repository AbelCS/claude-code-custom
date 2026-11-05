---
name: conventions-code
description: When deciding where code, a query or a permission check goes, adding a table, or changing how data is read or saved. The module shape, boundaries and data rules every project follows, on any stack.
---

# Code conventions

Say "Using conventions-code to ..." first. These rules hold on any stack. The project's stack file, in `${CLAUDE_PLUGIN_ROOT}/stacks/`, says how they map onto its framework and database. With no stack file, the mapping goes in the Code organisation section of `AGENTS.md`.

## The domain

- **Domain first:** model the business, not the screens. Name things as the people who do the work name them, and keep a glossary in `AGENTS.md`.
- Small, focused files, split when they grow unwieldy.
- A rule computed in two places gets a parity test running both on the same data.

## One shape for every module

Each module has the same parts, each with one job: contracts, queries, actions, tasks, input, rules, labels, ui.

| Part | Holds |
|---|---|
| contracts | The types and schemas other modules may use: the module's public face |
| queries | Reads. They fetch, and do nothing else |
| actions | Writes a person starts, run on the server |
| tasks | Work that runs without a person, on a schedule or in the background |
| input | Parsing and validating what comes in |
| rules | The domain's rules, as pure functions |
| labels | The words shown for the module's values, in one place |
| ui | The module's screens and components |

A module has only the parts it needs. Put new code in the part whose job it is, rather than a new kind of folder.

## Boundaries

Boundaries are lint errors, not review comments:

- Modules depend downwards only, and use another module only through its contracts.
- UI never reads the database directly. It goes through queries and actions.

If the linter can't express a boundary yet, add the rule that can, and say so.

## Reading data

- **A query fetches, a pure function shapes.** Reshaping, grouping and totals are named pure functions with unit tests, never buried in a query or a component.
- Complex reads also get tests against a real database, signed in as a real role.
- **Reads that list or total rows get every row.** Check the API's row limits, which often stop at a default page size without an error, and page by a unique key rather than an offset, so nothing repeats or goes missing while others write.

## Saving data and permissions

- Validate on the server. Checks in the browser are for the person's convenience only.
- Enforce permissions in the data layer as well as in code, and test them. That holds with or without row-level security: `references/data-layer.md` gives both routes.
- Every new table gets its access rules and a test of them, in the same pull request.
- A save changing several rows is all or nothing: one transaction.
- Prefer structured data over free text for anything searchable or counted.
- Don't overwrite history that has business value: append a new record instead.

## The database and the dev server

- Schema changes only through migrations, committed with the code that needs them.
- Never reset the owner's local database without asking. Tests use their own isolated stack.
- The owner's dev server may break while the agent works: work in place on the branch, and don't create a worktree to protect it.
