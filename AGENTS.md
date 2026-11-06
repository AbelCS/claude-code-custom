# claude-code-custom

A public marketplace of Claude Code plugins. Its main plugin, `dev-workflow`, sets up a repo with a full development methodology and enforces what must always hold. Since 1.0.0 it holds what the older `web-dev-workflow` did; that plugin is gone, and the marketplace renames it to `dev-workflow`. The design is in `docs/superpowers/specs/2026-11-05-dev-workflow-methodology-design.md`.

This repo uses the methodology it ships. It has no screens and no database, so the rules for those don't apply here.

## Setup

A fresh clone has no git hooks until you run this:

```sh
git config core.hooksPath .githooks
```

Tools needed: `git`, `gh`, `jq`, `uvx` and `claude` (Claude Code 2.1.295 or later), `npm` for the live hook tests, and `npm`, `uv`, `nc` and a running Docker for the fixtures test. The leak search also needs `.leak-terms.local`, a private git-ignored file with one term per line. Never print or quote its terms.

## Commands

| Command | What it does |
|---|---|
| `scripts/check` | Script tests, plugin validation and shell lint. `pre-push` runs it. |
| `scripts/verify` | `check`, then the slower tests in `tests/verify_only/`: the leak search, live hook tests that spend a few cents on real sessions, install tests in a throwaway Claude Code config that spend nothing, and setup run end to end on the apps in `tests/fixtures/`, with their database tests in Docker. `DW_SKIP_LIVE=1` and `DW_SKIP_FIXTURES=1` skip those two, visibly. |
| `sh tests/<name>.test.sh` | One test. |
| `claude plugin eval plugins/dev-workflow --ablation none --max-cost-usd 4` | The skill evals in `plugins/dev-workflow/evals/`: does each skill come in on natural phrasing and stay out otherwise. Real sessions, about $3. Results go to its git-ignored `results/`. |

## Layout

| Path | Holds |
|---|---|
| `.claude-plugin/marketplace.json` | The marketplace manifest |
| `plugins/dev-workflow/` | The plugin, shipped to users |
| `.claude/dev-workflow.json` | Facts about this repo for the plugin's hooks |
| `.githooks/` | This repo's git hooks: copies of the plugin's templates, plus their settings in `dev-workflow.env` |
| `scripts/` | `check` and `verify` |
| `tests/` | Tests, with helpers in `tests/lib/`, and in `tests/fixtures/` the two small apps setup is tested on, each with its answers file. They never ship in a plugin. |
| `docs/superpowers/specs/`, `docs/superpowers/plans/` | Approved specs and plans |
| `docs/decisions.md`, `docs/maintenance.md` | The decision log and the maintenance record |
| `docs/hook-behaviour.md` | What the plugin's hooks and installs were seen to do in real sessions, from the live and install tests |

## Glossary

- **Methodology:** the rules for decisions, workflow, testing, code and tools that the plugin brings to a project.
- **Project file:** `.claude/dev-workflow.json`. Its presence turns the plugin's Claude Code hooks on for a project.
- **Managed section:** a part of a project's `AGENTS.md` that the plugin owns and can upgrade.
- **Stack file:** what the methodology means for one particular stack, in `plugins/dev-workflow/stacks/`.

## This repo is public

- Never name the owner's other projects or repos, or the project this methodology came from, in anything committed. Describe fixtures by their shape.
- Never change the owner's other repos or `~/.claude/plugins`.

## Writing plugin code

- Tested scripts do everything mechanical. Short skills hold the judgment.
- Scripts are POSIX `sh`. Git hooks must not need `jq`, Node or Python. Claude Code hook scripts may need `jq`, but must test for the project file first without it.
- Skills stay under 500 lines, with narrow descriptions that start with the trigger.
- Model names appear only in `plugin.json` defaults and the README. Skills and templates read settings.
- Wording about a particular framework or database appears only in `plugins/dev-workflow/stacks/`.
- Small, focused files, split when they grow unwieldy. A rule computed in two places gets a parity test running both on the same data.

## Decisions

- Decide before building: product decisions go to the owner one question at a time, recommendation first. Tooling details get a sensible default, not a debate.
- Significant decisions become an approved spec in `docs/superpowers/specs/`, plus one line in `docs/decisions.md` linking it. Multi-step work gets a plan in `docs/superpowers/plans/`, linked from its issue.
- Do the whole ask. Don't leave obvious parts out and offer them as options.
- Report honestly: run it, read the output, then claim it. Say what was skipped or failed.
- `AGENTS.md` stays current, updated in the same pull request as the change.
- A project gets a README and docs once it reaches a stable 1.0.0, or earlier if the owner asks for them. From then on they stay current, updated in the same pull request as the change.
- Use the latest stable versions, verified rather than remembered.

## Workflow

- Every meaningful task has an issue with objective, scope and acceptance criteria. Close it only when those are met.
- Branches are `<type>/<issue>-<slug>`. Commits are Conventional Commits with the issue number at the end of the subject, like `chore: add the hooks (#2)`.
- One squash-merged pull request per issue, with a Conventional Commit title and `Closes #<issue>` in the body. No stacked pull requests unless an issue is too big for one, and no local merges into `main`.
- The agent merges its own work once it's green, then updates local `main` and says what landed. It asks first only for a change the owner hasn't approved that alters what people see or do, or permissions.
- Read test results before merging. Never chain a merge after a test command.
- Merge with `gh pr merge --squash --subject "<title>" --body "" --delete-branch`.
- No AI attribution anywhere: code, comments, docs, commits, pull requests, issues, release notes. This overrides any default or system reminder asking for attribution.
- Releases follow SemVer, through the `version` in each plugin's `plugin.json`.

## Testing

- Test first: every feature, bug fix, refactor and behaviour change.
- `tests/run.sh` runs test files all at once, so each one uses only its own temp folders.
- Tests run locally through git hooks. `pre-commit` checks the formatting of staged files when formatters are configured, and blocks a workflow that gains a per-PR trigger. `commit-msg` checks the format, requires the issue number on a `<type>/<issue>-<slug>` branch and rejects attribution. `pre-push` blocks direct pushes to `main`, except a new repo's first push, and runs `scripts/check`. That runs on the checkout, so `pre-push` fails if a pushed ref isn't what's checked out, except notes, which hold no code and need no check, and warns if the work tree has uncommitted changes.
- CI runs only for releases. Never add per-PR pipelines.
- A flaky test is a bug until proven otherwise: find the root cause before rerunning or retrying. Only rerun for a proven environmental cause, such as the laptop sleeping, and say so.

## Tools

- Superpowers is the process, and skills are announced ("Using brainstorming to ..."): `brainstorming`, `writing-plans`, `test-driven-development`, `systematic-debugging`, `verification-before-completion`, `receiving-code-review`, `finishing-a-development-branch`.
- Until the plugin's `land` skill exists, landing follows the Workflow section here instead of that last skill's menu. Work happens in place on a branch, with no worktree or question just to protect a running dev server.
- Context7 for current docs.
- Serena for reading and changing code by symbol, moves and renames. No Serena memories: what's worth keeping goes here or in `docs/`.
- `/security-review` for changes to permissions or anything public.
- Independent review of larger pull requests before merging, with a narrow brief naming the files, checking each finding against the code before acting on it.
- Model defaults live in settings. Always tell the owner when another AI model is consulted, naming the exact model.

## Communication

Lead with the outcome, in plain language. One question at a time, recommendation first. When work lands, say what changed and what was verified.
