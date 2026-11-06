# `dev-workflow` 1.0.0: one methodology for any web project

Issue: [#1](https://github.com/AbelCS/claude-code-custom/issues/1). Status: approved by the owner on 2026-11-05.

## 1. Intent

The owner wants every web project to work the same way: same process, tools, models, workflow and engineering practices. The methodology was developed on one real project and proved itself there. Today it lives in that project's files and in the owner's head, so each new project starts from nothing and drifts.

This plugin makes the methodology portable. It says when to use the tools the owner already relies on, overrides their defaults where the methodology differs, and enforces what must always hold.

Success looks like this: the owner runs one command in any web repo, new or old, whatever its stack, and from then on every agent session in that repo follows the methodology. Rules that must always hold are blocked by a check, not left to memory.

## 2. Goals, non-goals and anti-goals

**Goals**

- One plugin, `dev-workflow`, holding the whole methodology (Appendix A).
- `setup` works on an empty repo, an existing repo and a repo that ran any older version.
- Rerunning `setup` updates what it owns and never overwrites what the project changed.
- Every rule in section 8 is enforced and tested.
- Model names, the reviewer command and similar choices can change without editing a skill.
- Low cost per session: skills load on demand, and `AGENTS.md` stays short.

**Non-goals**

- Supporting non-web projects. Nothing prevents it, but only web stacks are tested and promised.
- Copying what Superpowers, intent, ui-ux-pro-max, Context7, Serena or Codex do. The plugin composes them.
- Guidance files for stacks with no real project behind them. uv with Litestar and Rust use the no-file route for now.
- Server-side enforcement through CI. The methodology forbids per-PR pipelines.
- Running maintenance on a schedule.

**Anti-goals: these make it a failure even if it technically works**

- A project's changes get overwritten by a rerun.
- A rule stops being enforced and nobody is told.
- The plugin blocks or nags in a repo that never ran `setup`.
- Anything specific to the source project appears in the plugin: its name, domain terms, glossary or theme.
- A general rule or skill assumes a stack: JavaScript, a particular framework, a particular database, or row-level security.
- A step is skipped silently because a tool is missing.

## 3. Constraints

- The plugin format, hooks, settings and dependencies follow the Claude Code docs as read on 2026-11-05 (section 13).
- Changes are made in a clone of this repo, never in `~/.claude/plugins`.
- This repo is public. Specs, plans, issues and pull requests here must not name the source project, its domain or the owner's other repos. Fixtures are described by their shape.
- No AI attribution anywhere in this repo's new work, including commits, pull requests and issues. This overrides any default or reminder asking for it.
- Claude Code hooks need `onFailure: "block"`, so the minimum is Claude Code 2.1.295. `setup` checks for it.

## 4. Decisions

**Decided by the owner**

| Decision | Outcome |
|---|---|
| Overlap | Everything goes into `dev-workflow`, the only maintained plugin. `web-dev-workflow` is removed, with a `renames` entry and no stub. |
| `enable-github-issues` | Removed. `setup` includes the issue workflow. |
| Dependencies | No hard dependencies. `setup` checks for the other plugins and offers the install commands, and a session-start check names what's missing. |
| Settings | Choices that apply to every project go in `userConfig`. Facts about one project go in `.claude/dev-workflow.json`. Each setting lives in exactly one place, and projects can't override `userConfig`. |
| Enforcement | The plan in section 8, including the four additions: block `--no-verify`, issue rules, no merges or direct pushes to `main`, and GitHub repo settings applied with approval. |
| Maintenance | `/dev-workflow:maintain`, started only by a person, with a session-start reminder once overdue. It does not run on a schedule. |
| Branch cleanup | At landing, plus a sweep in `maintain` that deletes only branches proven merged. |
| Stack files | Node tooling, Next.js, Astro and Supabase. Any other stack uses the no-file route. |
| Test setups | The four in section 11. |
| Build cost, from part 3 on (owner, 2026-11-05) | A fresh implementer per task, never resumed. No per-task review: one independent review per part before merging. Fix rounds only for problems in ordinary use, with edge cases listed. Two real test setups instead of four (section 11). |
| Delivery | #1 is split into smaller issues, each with its own squash-merged pull request, merged one at a time and not stacked: (1) this repo adopts the methodology, (2) enforcement, (3) `setup` and upgrades, (4) skills and stack files, (5) migration and 1.0.0. The agent merges each when green without asking, and the owner can stop it between steps. |

**Calls made while writing this document, open to challenge when reviewing it**

| Call | Reason |
|---|---|
| Two conventions skills rather than four, with testing rules in `AGENTS.md` | Each automatic skill adds a line to every session. |
| Claude Code hooks in POSIX `sh` plus `jq`, git hooks in `sh` only | No Node or Python assumption in a project. |
| Maintenance interval of 30 days, recorded in `docs/maintenance.md` | The date should travel with the repo. |
| Model routing stays as guidance | Skill `model` settings last one turn, and a project-level `model` would create a second place for the setting. The main session's model remains a person's choice. Subagents are given the model from settings. |
| Next.js and Supabase content is allowed only in separate stack files, as general public guidance | This is how the owner's "must not appear" and "separate parts" lines fit together. Nothing there comes from the source project. |
| Decision log at `docs/decisions.md` | A neutral name that any project can use. |
| "Larger" pull request means over 300 changed lines, or any change to permissions, sign-in, money rules or public surfaces | A default that can be changed in settings. Judgment can always ask for a review on smaller changes. |
| Fixtures are small real apps, and each has one real database test where it has a database | "Runs for real" should mean real. Supabase comes through the fixture's own dev dependency and Docker, so nothing is installed machine-wide. |
| In this repo, `check` covers script tests, enforcement tests, lint and validation. `verify` adds the fixtures and leak search. Evals are run separately. | `pre-push` has to stay fast, and fixtures need Docker and several minutes. |
| No machine-wide installs for the build | Tests run in plain `sh`, and shell linting runs through `uvx`. |
| Old commit trailers in this repo's history stay | Rewriting public history is hard to undo and can be done later if wanted. New work carries none. |

## 5. Plugin layout

```text
plugins/dev-workflow/
  .claude-plugin/plugin.json     version 1.0.0, author, userConfig
  skills/
    setup/                       SKILL.md, references/, templates/
    choose-stack/
    land/
    independent-review/
    screen-check/
    conventions-code/
    conventions-ui/
    maintain/
    enable-releases/
  stacks/                        node-tooling.md, nextjs.md, astro.md, supabase.md
  hooks/hooks.json
  scripts/                       Claude Code hook scripts and setup's deterministic work
  evals/
```

- `commands/` goes away: the docs say to prefer skills, and a skill already provides the `/dev-workflow:<name>` command. Today's `setup` exists as both, which shows up as a duplicate.
- `plugins/web-dev-workflow/` is deleted.
- Don't add a top-level `bin/`. It stops the plugin syncing through claude.ai organization settings, and `scripts/` works everywhere.
- `.DS_Store` is ignored, since the validator flags it.

## 6. Settings

### `userConfig`: the owner's choices, shown in `/config`

Read through `${user_config.KEY}` in skills and `CLAUDE_PLUGIN_OPTION_<KEY>` in hooks.

| Key | Default |
|---|---|
| `model_noncoding` | `claude-fable-5-1`, for research, product thinking and design critique |
| `model_noncoding_alt` | `gpt-6-astra` (OpenAI, through the Codex CLI), the same work's alternative |
| `model_docs` | `claude-sonnet-5-5`, for docs, READMEs and similar writing (owner, 2026-11-06) |
| `effort_docs` | `high` (owner, 2026-11-06) |
| `model_coding` | `claude-opus-5-5` |
| `effort_coding` | `high` |
| `reviewer_name` | `GPT-6.1 Sol (OpenAI, high effort, read-only)`, shown when announcing a review |
| `reviewer_command` | `codex exec -m gpt-6.1-sol -c model_reasoning_effort=high --sandbox read-only "<brief>" < /dev/null` |
| `review_threshold_lines` | `300` |
| `maintenance_interval_days` | `30` |

The README lists every key and how to change it. `gpt-6-astra` and `gpt-6.1-sol` were confirmed in the local Codex model list on 2026-11-05.

### `.claude/dev-workflow.json`: facts about one project, committed

Written by `setup`. Its presence is what turns the plugin's hooks on for a project.

```json
{
  "schemaVersion": 1,
  "pluginVersion": "1.0.0",
  "stack": ["node-tooling", "nextjs", "supabase"],
  "hasScreens": true,
  "commands": {
    "format": "npm run format",
    "formatCheckStaged": "...",
    "check": "npm run check",
    "verify": "npm run verify",
    "deadCode": "npm run knip",
    "audit": "npm audit"
  },
  "testCommands": ["npm test", "npx playwright test"],
  "databaseResetCommands": ["npm run db:reset"],
  "ciAllowlist": [".github/workflows/release-check.yml"],
  "managed": {
    "AGENTS.md#workflow": "<fingerprint>",
    ".githooks/commit-msg": "<fingerprint>"
  }
}
```

The builder may adjust the field names. The requirements are that a command can hold several formatters for a mixed repo, a missing `check` command fails visibly, and the file validates against a schema with a clear error.

## 7. `setup`

Automatic for a new project, or `/dev-workflow:setup`. The skill holds the judgment, and tested scripts do the mechanical work: fingerprints, block replacement, JSON merges and hook installation.

### Flow

1. **Detect:** empty, existing or old setup. Stack markers. Existing hook tools (husky, lefthook, others). The GitHub remote.
2. **Check tools,** and report each as present or missing with its exact install command:
   - Required: `git`, `gh` (signed in), `jq`, Claude Code 2.1.295 or later. Stop if any is missing.
   - Plugins: Superpowers, Context7, Serena, intent and ui-ux-pro-max. Offer to install. Check that the Superpowers skills the methodology relies on still exist, since no version can be pinned.
   - Other: Codex CLI and a browser tool. Missing means the matching step warns; it never skips silently.
3. **Ask what it can't detect,** one question at a time, recommendation first: the stack (handing to `choose-stack` if undecided), commands, whether the project has screens, whether it has a database, and any reset commands.
4. **Show the plan:** every file to create, update or leave, and which project-edited parts differ. Write nothing before the person agrees.
5. **Write:**
   - `AGENTS.md` from the template, with managed sections.
   - `CLAUDE.md` containing exactly `@AGENTS.md`. Existing content moves into `AGENTS.md` first, and nothing is dropped.
   - `docs/superpowers/specs/`, `docs/superpowers/plans/`, `docs/decisions.md`, `docs/maintenance.md`.
   - Git hooks, adapted to the stack, activated with the stack's mechanism (a `prepare` script for Node, `git config core.hooksPath .githooks` otherwise) or added into an existing hook tool.
   - `.claude/dev-workflow.json`.
   - In `.claude/settings.json`, merged with what's there: `"attribution": { "commit": "", "pr": "", "sessionUrl": false }`. This form is used because `"attribution": false` makes older versions reject the whole file.
   - With approval: the `gh pr merge` permission in `.claude/settings.local.json`, because auto mode can otherwise block self-merging.
   - With approval on that repo: GitHub settings for squash merges only, a blank squash message, the pull request title as the subject, and deleting merged branches.
6. **Report:** what was written, updated, migrated and left alone, what's still missing, and how to turn hooks on in a fresh clone.

### Upgrades and reruns

- **Managed sections:** each section in `AGENTS.md` sits between comment markers naming the section. A fingerprint of its text is stored in `.claude/dev-workflow.json`.
- **On a rerun:** fingerprint unchanged means replace with the new text. Changed means the project edited it, so leave it and show the difference. Sections outside the markers are never touched.
- **Other generated files** (git hooks, for example) use the same ledger.
- **Old blocks have no markers.** They're recognised by exact comparison against every text published in this repo's history: `## Web Dev Workflow Rules`, its six subsections, and `## GitHub Issue-Driven Workflow`, in `AGENTS.md` or `CLAUDE.md`. A subsection that matches a published text is replaced. One that doesn't is kept and shown as a difference.
- **Old pointers:** every `CLAUDE.md` pointer form published here counts as a pointer, and is replaced with the import.
- **Second run:** with no plugin change, a rerun changes no files and says so.

## 8. Enforcement

Two layers. Git hooks are copied into the project and work for anyone, with or without the plugin. Claude Code hooks ship in the plugin, act only in projects with `.claude/dev-workflow.json`, check that file before anything that needs `jq`, and use `onFailure: "block"`, so a broken check blocks rather than lets a command through.

These checks catch mistakes. They aren't a security boundary, and the docs say the same of command-text matching.

| Rule | Mechanism | Blocks | Allows |
|---|---|---|---|
| Attribution in commits | `.claude/settings.json`, `commit-msg` | `Co-Authored-By` naming an AI tool, "generated with" lines | Human co-authors, ordinary mentions of a tool as a subject of the change |
| Attribution in pull requests, issues, comments and releases | Claude Code hook on `gh` commands and GitHub MCP tools, reading title, body and body files | The same text, in any of those | Clean text |
| Squash without a default message | Claude Code hook on `gh pr merge` | Merges without `--squash` and `--body ""` | `gh pr merge --squash --subject "..." --body ""` |
| Conventional Commits | `commit-msg` | Anything else, including `Merge...` | `feat(scope)!: subject (#12)`, `fixup!` and `squash!` during work |
| Issue number in commits | `commit-msg`, on `<type>/<issue>-<slug>` branches | A subject without that issue number | A subject with it, and branches outside that pattern |
| Pull request title and closing keyword | Claude Code hook on `gh pr create` and `gh pr edit` | A non-conventional title, a missing `Closes #<issue>` | Both present |
| `pre-push` runs `check` | `pre-push`, using the configured command | Failing checks, a missing `check` command | Passing checks |
| Direct push to `main` | `pre-push` | Pushing to the default branch | A new repo's first push, and other branches |
| Local merge into `main` | Claude Code hook | `git merge` while on the default branch | Merges on work branches, `gh pr merge` |
| `--no-verify` | Claude Code hook on `git commit` and `git push` | The flag and its `-n` form on `git commit` | Commands without it, `--no-verify`-like text in a message |
| Database reset needs a yes | Claude Code hook returning `"ask"`, from `databaseResetCommands` plus the stack file's list | Runs only after a person approves | Other commands, migrations, a reset inside the isolated test stack's script |
| Merge chained after tests | Claude Code hook, splitting on `&&`, `\|\|`, `;`, `\|`, `&` and newlines | A merge after anything in `testCommands`, `check` or `verify` | Tests alone, a merge alone, a merge followed by `git pull` |
| Per-PR CI | Claude Code hook on Write and Edit returning `"ask"`; `pre-commit` on staged workflows | A workflow gaining a `pull_request`, `pull_request_target` or `push` trigger | `workflow_dispatch`, schedules on release workflows, files in `ciAllowlist` |
| Formatting | `pre-commit`, on staged files only | Unformatted staged files | Formatted files, nothing staged |

Each row gets a test of both columns. Add a test that hooks do nothing in a repo without `.claude/dev-workflow.json`, and a test that a broken check blocks.

To verify in testing, not assume: `"ask"` under auto mode (the docs say it still prompts), and under `claude -p` (expected to be denied, not documented). If `"ask"` can pass without a person anywhere, the reset rule becomes a deny with a project-level way to allow it.

### Session-start check

Only in projects with `.claude/dev-workflow.json`, and silent when all is well. One line each for: git hooks not active, a required plugin or tool missing, managed sections older than the installed plugin, maintenance overdue. It must stay fast, so it reads files rather than starting anything slow.

### What stays as guidance

Test-first, short labels, root-causing flaky tests, doing the whole ask, honest reporting, reading test results before merging, and the code and UI conventions. These need judgment, so they stay in `AGENTS.md` and skills.

## 9. Skills

Descriptions are narrow and start with the trigger. Bodies stay short, with detail in reference files.

| Skill | Invocation | Must do |
|---|---|---|
| `setup` | Automatic and command | Section 7. |
| `choose-stack` | Automatic | Decide a stack from where it runs, who operates it, data limits, licences, what a PoC needs and what production needs. No default vendor. One question at a time. Verify current versions. Record the outcome as a spec plus a decision-log line. |
| `land` | Automatic | Section 9.1. |
| `independent-review` | Automatic and from `land` | Announce the exact model before calling it. Use `reviewer_command` with a narrow brief naming the files. Check each finding against the code (`receiving-code-review`) before acting. Report what it was asked and what it found, attributing the findings to that model. Fail visibly if Codex is missing, and ask rather than skip. |
| `screen-check` | Automatic after UI changes | Every touched screen in a browser or Playwright: light, dark, a 360 px phone, keyboard, plus empty, filled and long states. Fix what's found before reporting. Fail visibly if no browser tool is available. |
| `conventions-code` | Automatic | Appendix A's Code section, stated in general terms. Stack mapping comes from the stack files. Database rules work with or without row-level security. |
| `conventions-ui` | Automatic | Appendix A's UI and UX section, including copy. |
| `maintain` | Command only (`disable-model-invocation`) | Section 9.2. |
| `enable-releases` | Command only | Release-please from a manually run workflow, plus an optional check that runs only on release pull requests and goes in `ciAllowlist`. Verify the current action version. Detect the release type as today's command does. Stop and ask before overwriting. |

### 9.1 `land`

Replaces the Superpowers `finishing-a-development-branch` menu, with no merge / pull request / keep question.

1. Confirm the issue's acceptance criteria are met.
2. Run `verify` as its own command, and read the result. Never chain a merge after it.
3. Run `independent-review` if the change is larger.
4. Run `screen-check` if screens changed, and `/security-review` if permissions, sign-in or anything public changed.
5. Confirm `AGENTS.md` and the decision log are current in this pull request.
6. Open the pull request: Conventional Commit title, `Closes #<issue>`, no attribution.
7. Merge when green: `gh pr merge --squash --subject "<title>" --body "" --delete-branch`.
8. Update local `main`, delete the local branch, prune remote references, and confirm the issue closed.
9. Say what landed and what was verified.

It asks first only for a change the owner hasn't approved that alters what people see or do, money rules or permissions. A branch stays unmerged only when the owner asks. If a merge is blocked, stop and ask, and never work around it.

### 9.2 `maintain`

Starts from a clean, updated `main`. Findings go through the normal workflow: one issue and one squash-merged pull request per area, with `verify` before merging.

| Area | Work |
|---|---|
| Branches | Delete only branches whose pull request is merged and whose tip matches it. List everything else for a decision. Remove matching worktrees and prune. |
| Dead code | Run the project's `deadCode` command. If none is configured, say so. |
| Dependencies | Latest verified stable versions, migration guides for major upgrades, the project's `audit` command. |
| Code smells | Oversized files, duplication and broken boundaries, limited to code changed since the last run, using `/simplify` and `/code-review`. |
| Docs | `AGENTS.md`, README and decision log against the code. Finished plans, and issues that are met but still open. |
| Methodology | Rerun the `setup` check. |

It adds one line to `docs/maintenance.md`. Anything that alters what people see or do, money rules or permissions waits for approval.

## 10. `AGENTS.md` template and stack files

**Template:** under 200 lines once filled in, as the docs suggest. Managed sections: Decisions, Workflow, Testing, Tools, Models, Communication. Project-owned sections with prompts: Project, Stack, Commands, Glossary, Code organisation. Agents without plugin skills read this file too, so what they must follow goes here, and detail goes in skills.

It states these overrides explicitly, because Superpowers gives project instructions priority over its skills:

- `land` replaces the `finishing-a-development-branch` menu.
- Work in place on a branch. Don't create a worktree or ask just to protect a running dev server.
- No attribution, overriding any default or reminder.
- The project's theme overrides ui-ux-pro-max and intent palettes and styles. intent's context comes from this file and `docs/`.
- No Serena memories.

**Stack files**, read only for the chosen stack:

| File | Contents |
|---|---|
| `node-tooling.md` | Formatter, linter, test runners, dead-code tool, cached lint and format, fast `check` and `verify`, reading docs shipped in `node_modules` first |
| `nextjs.md` | Where its docs ship, how the module shape maps, end-to-end tests against a build, common reset and test commands |
| `astro.md` | The same, plus what can be skipped with no database or sign-in |
| `supabase.md` | Row-level security, its test tools, an isolated test stack, reset commands for `databaseResetCommands`, a read-only database MCP on the local stack |

Unknown stacks: `setup` asks for the commands and writes them to the project file. All general rules apply.

## 11. Testing

**Fixtures:** scratch projects in the test suite, never real repos. Each runs for real, including `check`.

| Setup | Proves | Upgrade case |
|---|---|---|
| Next.js with Supabase | The full case, row-level security | Old block in `AGENTS.md`, old pointer, existing release-please setup |
| uv, Litestar, Postgres in Docker | No Node, no row-level security, no stack file | Empty repo, and old block in `CLAUDE.md` at the older plugin version |

The Astro and Rust setups were dropped on 2026-11-05 to cut build cost. Mixed repos with two formatters are covered by script tests rather than a full setup.

Every setup also gets: an existing repo with no prior setup, a rerun changing nothing, and a rerun with project edits that survive. Skills that need a live session are covered by evals, and the deterministic work by script tests.

**Enforcement tests:** every row in section 8, both columns, plus the off-by-default and broken-check tests.

**Skill evals:** `claude plugin eval`, one case per skill that should fire (`tool_used: Skill`) and one that shouldn't (`min: 0`, `max: 0`), with `--max-cost-usd` set. Every case is a full Claude run, so the suite is run deliberately rather than in `check`. If the command is unavailable (the docs mention early access), use the skill-creator tooling and say so.

**Install tests:** `claude plugin validate --strict`, a real install from a local marketplace, the `renames` migration (including the documented "not cached" case), and the update path.

**Leak search:** a test in `verify` that fails if the plugin contains the source project's name, domain terms, glossary or theme. The term list stays out of this public repo, in `.leak-terms.local`, git-ignored, with one case-insensitive term per line. The builder drafts it from the source material at the start of the build. If the file is missing, the test fails visibly rather than passing.

**Stack-word search:** Next.js, Supabase and row-level security wording may appear only in `stacks/`, apart from the general "with or without row-level security" database rule.

## 12. Migration and this repo

**Marketplace:** remove `web-dev-workflow`, add `"renames": { "web-dev-workflow": "dev-workflow" }`, and add author details.

**Version:** `dev-workflow` 1.0.0. `version` in `plugin.json` only. If the install tests show moving from `web-dev-workflow` 1.2.0 to 1.0.0 fails as a downgrade, use 2.0.0 and tell the owner.

**README:** installation, updating, every setting, how to change a default, and upgrade notes. Auto-update is off for this marketplace by default, so the update steps are:

```text
/plugin marketplace update claude-code-custom
claude plugin update dev-workflow@claude-code-custom
/reload-plugins
```

**Upgrade notes must say:**

- `/web-dev-workflow:setup` and `/dev-workflow:enable-github-issues` are gone. Use `/dev-workflow:setup`.
- Old projects keep working, but their rules don't load until `setup` is rerun because of the `CLAUDE.md` pointer bug.
- `enable-releases` now creates a manually run workflow. Existing workflows aren't changed.
- A machine that never installed `dev-workflow` may need one `/plugin install dev-workflow@claude-code-custom`, if testing confirms the "not cached" case.
- Which repos need a rerun is up to the owner. Nothing changes them automatically.

**This repo adopts the methodology:** `AGENTS.md`, `CLAUDE.md` with the import, `.gitignore`, hooks, `check` and `verify` commands, `docs/decisions.md`, GitHub settings with approval, and no attribution in new work. It's a plugin repo with no screens, so the screen rules don't apply.

## 13. Documentation these decisions rest on

Read on 2026-11-05. Reread before relying on details, since these change.

| Topic | Page | Fact relied on |
|---|---|---|
| `AGENTS.md` | `/docs/en/memory` | With a `CLAUDE.md` present, only `CLAUDE.md` loads. An `@` import brings `AGENTS.md` in. |
| Manifest | `/docs/en/plugins-reference` | `userConfig`, `dependencies`, `version`, `${user_config.KEY}`, `CLAUDE_PLUGIN_OPTION_<KEY>` |
| Dependencies | `/docs/en/plugin-dependencies`, troubleshooting | A missing dependency keeps the plugin disabled. Cross-marketplace needs an allowlist. |
| Settings | `/docs/en/settings`, settings reference | `pluginConfigs` is user or managed only. `attribution` works in any file. |
| Hooks | `/docs/en/hooks`, `/docs/en/permissions` | Decisions, exit codes, `onFailure`, and hooks and allow rules |
| Skills | `/docs/en/skills` | Frontmatter, `model` lasting one turn, `disable-model-invocation` removing the description from context |
| Evals | `/docs/en/plugin-evals.md` | Case format, `tool_used` with `min` and `max` |
| Updates and renames | `plugins/loading.md`, `plugins/host-marketplace.md` | Version resolution, auto-update off by default, `renames` |

## 14. Left to the builder

- The test framework for this repo, as long as it runs locally and `check` stays fast.
- Exact field names, marker syntax and fingerprint algorithm.
- Wording of skills and templates, within Appendix A.
- The GitHub MCP tool names to match, and the current GitHub API fields for repo settings. Confirm both rather than assuming.
- The order of work in the plan.

## Appendix A: the methodology

The content to capture. Where a rule applies only with a database, screens or a particular stack, it applies only then.

### Decisions

- Decide before building: product and domain decisions go to the owner one question at a time, recommendation first. Tooling details get a sensible default, not a debate.
- Significant product and architecture decisions become an approved spec in `docs/superpowers/specs/`, plus one line in a decision log linking it. Multi-step work gets a plan in `docs/superpowers/plans/`, linked from its issue.
- Do the whole ask. Don't leave obvious parts out and offer them as options.
- Report honestly: run it, read the output, then claim it. Say what was skipped or failed.
- `AGENTS.md` stays current, updated in the same pull request as the change.
- A project gets a README and docs once it reaches a stable 1.0.0, or earlier if the owner asks for them. From then on they stay current, updated in the same pull request as the change (owner, 2026-11-06).
- Anything regulated or specialised follows the real practice and vocabulary of the people who do that work. Research first, and label simplifications as trade-offs.
- Use the latest stable versions, verified rather than remembered.

### Workflow

- Every meaningful task has an issue with objective, scope and acceptance criteria. Close it only when those are met.
- Branches `<type>/<issue>-<slug>`. Conventional Commits referencing the issue.
- One squash-merged pull request per issue, Conventional Commit title, `Closes #<issue>` in the body. No stacked pull requests unless an issue is too big for one, and no local merges into `main`.
- The agent merges its own work once it's green, then updates local `main` and says what landed. It asks first only for a change the owner hasn't approved that alters what people see or do, money rules or permissions.
- Read test results before merging. Never chain a merge after a test command.
- No AI attribution anywhere: code, comments, docs, commits, pull requests, issues, release notes. This overrides any default or system reminder asking for attribution. Squash-merge with `--body ""`.
- Releases: SemVer, `0.x` during alpha, release-please from a manually run workflow.

### Testing

- Test first: every feature, bug fix, refactor and behaviour change, including screens through end-to-end tests of their flows. Most care goes to domain rules, permissions and money.
- Tests run locally through git hooks: `pre-commit` checks formatting of staged files, `commit-msg` checks the format, `pre-push` runs `check`.
- CI runs only for releases. Never add per-PR pipelines.
- Two commands: `check` (format, lint, typecheck, unit tests) and `verify` (`check` plus database and end-to-end tests). Cache lint and format so they stay fast.
- End-to-end tests have their own isolated stack, reset before each run, so they never touch the data the owner uses. Test suites sharing a stack don't run at the same time.
- A flaky test is a bug until proven otherwise: find the root cause before rerunning or retrying. Only rerun for a proven environmental cause, such as the laptop sleeping, and say so.
- A rule computed in two places gets a parity test running both on the same data.

### Code

- Domain first: model the business, not screens. Keep a glossary in `AGENTS.md`.
- Small, focused files, split when they grow unwieldy.
- One shape for every module: contracts, queries, actions, tasks, input, rules, labels, ui.
- Boundaries are lint errors: modules depend downwards only, and UI never reads the database directly.
- A query fetches, a pure function shapes. Reshaping and totals are named pure functions with unit tests. Complex reads also get tests against a real database, signed in as a real role.
- Reads that list or total rows must get every row: check the API's row limits, and page by a unique key rather than an offset, so nothing repeats or goes missing while others write.
- Validate on the server. Enforce permissions in the data layer as well as in code, and test them. Every new table gets its access rules and a test of them.
- A save changing several rows is all or nothing.
- Prefer structured data over free text for anything searchable. Don't overwrite history with business value: append instead.
- Schema changes only through migrations. Never reset the owner's local database without asking.
- The owner's dev server may break while the agent works: work in place.

### UI and UX

- UX is a first-class requirement. Check every touched screen in a browser before calling it done (light, dark, a 360 px phone, keyboard) and fix what you find before reporting.
- Build from a design system: primitives plus project patterns, with a showcase page in the app. Look there before creating something new, and add new patterns there.
- **Short labels, hard rule:** one word or as few as possible. Explanations go in a tooltip only where needed.
- **Never say it twice:** a tooltip, hint or description adds only what isn't visible, and no two places say the same thing. Reread every string before delivering it. Mark optional fields quietly, never "(optional)".
- Theme tokens only, never raw palette colours. One type scale. Motion tokens that respect reduced motion. Formatting of money and dates goes through one helper.
- Accessibility: contrast 4.5:1 for text and 3:1 for field outlines, icons and chart marks, visible focus, accessible names, never colour alone, a menu equivalent for drag and drop, a skip link, a screen-reader summary for charts.
- Everything clickable shows the hand cursor, through one global rule. Explanations open on hover, keyboard focus and tap: never rely on a native `title`, except for the full value of cut-off text.
- Nothing is wider than a 360 px phone: wide tables scroll inside their card. Fields are 16 px on touch screens so iPhones don't zoom, and controls grow to 40 px there while the desktop stays dense.
- Every page has its own loading skeleton. Saves that never reach the server show a connection error instead of hanging.

### Tools

- Superpowers is the process, and skills are announced ("Using brainstorming to …"): `brainstorming`, `writing-plans`, `test-driven-development`, `systematic-debugging`, `verification-before-completion`, `receiving-code-review`, `finishing-a-development-branch` (replaced by `land`).
- Context7 for current docs. If a framework ships docs in `node_modules`, read those first.
- Serena for reading and changing code by symbol, moves and renames. No Serena memories: what's worth keeping goes in `AGENTS.md` or `docs/`.
- A read-only database MCP on the local stack, when the database has one.
- intent for UX thinking, ui-ux-pro-max for UI guidelines and accessibility checks. A project's own theme always wins.
- `/security-review` for changes to permissions, sign-in or anything public.
- A browser or Playwright for screen checks.
- Independent review of larger pull requests before merging, with a narrow brief naming the files, checking each finding against the code before acting on it.

### Models

Defaults, kept in settings:

- Sonnet 5.5 at High effort for docs, READMEs and similar writing (owner, 2026-11-06).
- Fable 5.1 or GPT-6 Astra for research, product thinking and design critique (owner, 2026-11-06).
- Opus 5.5 at High effort for coding.
- GPT-6.1 Sol, always at High effort with the explicit flag, for code reviews.
- Always tell the owner when another AI model is consulted, naming the exact model.

### Communication

Lead with the outcome, in plain language. One question at a time, recommendation first. When work lands, say what changed and what was verified.
