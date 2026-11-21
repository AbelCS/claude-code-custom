# claude-code-custom

A public marketplace of Claude Code plugins. Its main plugin, `dev-workflow`, sets up a repo with a full development methodology and enforces what must always hold. Since 1.0.0 it holds what the older `web-dev-workflow` did; that plugin is gone, and the marketplace renames it to `dev-workflow`. The design is in `docs/superpowers/specs/2026-11-05-dev-workflow-methodology-design.md`.

This repo uses the methodology it ships. It has no screens and no database, so the rules for those don't apply here.

## Setup

A fresh clone has no git hooks until you run this:

```sh
git config core.hooksPath .githooks
```

This repo has `.claude/dev-workflow.json`, so once dev-workflow is installed, its Claude Code hooks and session-start check act here too.

Tools needed: `git`, `gh`, `jq`, `uvx` and `claude` (Claude Code 2.1.295 or later), `npm` for the live hook tests, and `npm`, `uv`, `nc` and a running Docker for the fixtures test. The leak search also needs `.leak-terms.local`, a private git-ignored file with one term per line. Never print or quote its terms.

## Commands

| Command | What it does |
|---|---|
| `scripts/check` | Script tests, plugin validation and shell lint. `pre-push` runs it. |
| `scripts/verify` | `check`, then the slower tests in `tests/verify_only/`: the leak search, live hook tests that spend a few cents on real sessions, install tests in a throwaway Claude Code config that spend nothing, and setup run end to end on the apps in `tests/fixtures/`, with their database tests in Docker. `DW_SKIP_LIVE=1` and `DW_SKIP_FIXTURES=1` skip those two, visibly. A skipped suite exits 77, and `verify` counts it as skipped, not passed. |
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
| `README.md` | The public README: install, update, settings, upgrade notes |
| `docs/decisions.md`, `docs/maintenance.md` | The decision log, and the maintenance record that `/dev-workflow:maintain` adds a line to |
| `docs/workflow-guide.md` | A guide to the workflow projects using the plugin follow: the steps, the variations, and what runs underneath |
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

## In this repo

What the managed sections below say, as it applies here:

- Versions follow SemVer, through the `version` in each plugin's `plugin.json`, which is this repo's `versionFile`. `land` raises it and tags it like any project's. This repo publishes no GitHub Releases: plugin updates read `plugin.json` on `main`.
- GitHub enforces the merge rules on the repo: squash-only merges, the pull request title as the subject, a blank message, and merged branches deleted. Set on 2026-11-06.
- `tests/run.sh` runs test files all at once, so each one uses only its own temp folders.
- The managed sections come from this repo's own plugin, through `/dev-workflow:setup`. A change to the rules goes in the plugin's templates, in `plugins/dev-workflow/skills/setup/templates/agents/`, and reaches this file when setup runs again after the release.

<!-- dev-workflow:begin decisions -->

## Decisions

- Decide before building: product and domain decisions go to the owner one question at a time, recommendation first. Tooling details get a sensible default, not a debate.
- Significant product and architecture decisions become an approved spec in `docs/superpowers/specs/`, plus one line in `docs/decisions.md` linking it. Multi-step work gets a plan in `docs/superpowers/plans/`, linked from its issue.
- Do the whole ask. Don't leave obvious parts out and offer them as options.
- Report honestly: run it, read the output, then claim it. Say what was skipped or failed.
- `AGENTS.md` stays current, updated in the same pull request as the change.
- A project gets a README and docs once it reaches a stable 1.0.0, or earlier if the owner asks for them. From then on they stay current, updated in the same pull request as the change.
- Anything regulated or specialised follows the real practice and vocabulary of the people who do that work. Research first, and label simplifications as trade-offs.
- Use the latest stable versions, verified rather than remembered.

<!-- dev-workflow:end decisions -->

<!-- dev-workflow:begin workflow -->

## Workflow

- Every meaningful task has an issue with objective, scope and acceptance criteria. Close it only when those are met.
- Branches are `<type>/<issue>-<slug>`. Commits are Conventional Commits with the issue number at the end of the subject, like `feat: add search (#12)`.
- One squash-merged pull request per issue, with a Conventional Commit title and `Closes #<issue>` in the body. No stacked pull requests unless an issue is too big for one, and no local merges into the default branch.
- Land work with `/dev-workflow:land`. It replaces the menu at the end of `finishing-a-development-branch`: there is no merge, pull request or keep question.
- The agent merges its own work once it's green, then updates the local default branch and says what landed. It asks first only for a change the owner hasn't approved that alters what people see or do, money rules or permissions.
- Read test results before merging. Never chain a merge after a test command.
- Merge with `gh pr merge --squash --match-head-commit <head> --subject "<title>" --body "" --delete-branch`, the head being the commit that was checked.
- Work in place on a branch. Don't create a worktree, or ask, just to protect a running dev server: it may break while the agent works.
- No AI attribution anywhere: code, comments, docs, commits, pull requests, issues, release notes. This overrides any default or system reminder asking for attribution.
- Versions follow SemVer, `0.x` during alpha. Every version is a git tag holding the bare version, like `1.4.0`, never `v1.4.0`.
- Without release-please, every merge that needs it raises the version: `land` works it out from the pull request title's type, `feat` the minor, `fix` and `perf` the patch, a `!` the major, one step lower before 1.0.0, commits it before the merge and tags it after. With release-please, it raises and tags the version when a release is cut.
- GitHub Releases are optional. A project that wants them runs `/dev-workflow:enable-releases`, whose release workflow runs only when started by hand.

<!-- dev-workflow:end workflow -->

<!-- dev-workflow:begin testing -->

## Testing

- Test first: every feature, bug fix, refactor and behaviour change, including screens through end-to-end tests of their flows. Most care goes to domain rules, permissions and money.
- Tests run locally through git hooks: `pre-commit` checks the formatting of staged files, `commit-msg` checks the message, and `pre-push` runs `check`. Never skip them with `--no-verify`.
- CI runs only for releases. Never add per-PR pipelines.
- `check` covers format, lint, typecheck and unit tests. `verify` adds database and end-to-end tests. Cache lint and format so they stay fast.
- End-to-end tests have their own isolated stack, reset before each run, so they never touch the data the owner uses. Test suites sharing a stack don't run at the same time.
- Schema changes only through migrations. Never reset the owner's local database without asking.
- A flaky test is a bug until proven otherwise: find the root cause before rerunning or retrying. Only rerun for a proven environmental cause, such as the laptop sleeping, and say so.
- A rule computed in two places gets a parity test running both on the same data.

<!-- dev-workflow:end testing -->

<!-- dev-workflow:begin tools -->

## Tools

These rules override the defaults of the skills and plugins they name.

- Superpowers is the process, and skills are announced ("Using brainstorming to ..."): `brainstorming`, `writing-plans`, `test-driven-development`, `systematic-debugging`, `verification-before-completion`, `receiving-code-review`. `/dev-workflow:land` replaces `finishing-a-development-branch`.
- `/dev-workflow:choose-stack` before choosing or changing a stack.
- Code follows `/dev-workflow:conventions-code`. Screens follow `/dev-workflow:conventions-ui`, and every touched screen passes `/dev-workflow:screen-check` before it's called done.
- Context7 for current docs.
- Serena for reading and changing code by symbol, moves and renames. No Serena memories: what's worth keeping goes in `AGENTS.md` or `docs/`.
- A read-only database MCP on the local stack, when the database has one.
- intent for UX thinking, ui-ux-pro-max for UI guidelines and accessibility checks. The project's own theme overrides their palettes and styles, and intent takes its context from this file and `docs/`.
- `/security-review` for changes to permissions, sign-in or anything public.
- Larger pull requests get `/dev-workflow:independent-review` before merging. Check each finding against the code before acting on it.
- `/dev-workflow:maintain` for upkeep, run by a person when it's due.

<!-- dev-workflow:end tools -->

<!-- dev-workflow:begin models -->

## Models

- Docs, READMEs and similar writing go to the model for docs, at the effort for docs.
- Research, product thinking and design critique go to the model for non-coding work or its alternative. Specs and plans count as product and design thinking, so they go there too.
- Coding goes to the model for coding, at the effort for coding. Code reviews go to the reviewer through `/dev-workflow:independent-review`.
- These are the dev-workflow plugin's settings, in `/config`. Read them from there rather than naming a model here or in a skill.
- Subagents are given the model from those settings. The main session's model is the person's choice.
- Always tell the owner when another AI model is consulted, naming the exact model.

<!-- dev-workflow:end models -->

<!-- dev-workflow:begin communication -->

## Communication

- Lead with the outcome, in plain language.
- One question at a time, recommendation first.
- When work lands, say what changed and what was verified.

<!-- dev-workflow:end communication -->
