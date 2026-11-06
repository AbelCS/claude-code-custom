# `dev-workflow` 1.0.0 Implementation Plan

**Status:** All five parts were done and merged by 2026-11-06, in PRs 7, 9, 10, 11 and 12. The checkboxes below weren't ticked as work went on, because progress was tracked in the issues and pull requests.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Merge `web-dev-workflow` into one plugin, `dev-workflow`, that sets up any web repo with the full methodology, enforces what must always hold, and upgrades old setups without overwriting project changes.

**Architecture:** Tested POSIX `sh` scripts do everything mechanical, and short skills hold the judgment. Git hooks are copied into each project so they work without the plugin. Claude Code hooks ship in the plugin and act only in projects with `.claude/dev-workflow.json`.

**Tech Stack:** POSIX `sh`, `jq`, `awk`, `git`, `gh`, Claude Code plugin format. Fixtures use Node, uv, Cargo and Docker.

**Spec:** `docs/superpowers/specs/2026-11-05-dev-workflow-methodology-design.md`. Read it first. Appendix A is the methodology content, and section numbers below refer to it.

## Delivery

One issue, one branch and one squash-merged pull request per part, merged in order and not stacked.

From part 3 on (owner, 2026-11-05): a fresh implementer per task, never resumed, and no per-task review. One independent review per part before merging. Fix rounds only for problems in ordinary use, with edge cases listed in the ledger. Each commit subject carries that part's issue number.

| Part | Issue | Branch | Tasks |
|---|---|---|---|
| 1. Adopt in this repo | #2 | `chore/2-adopt-methodology` | 1-2 |
| 2. Enforcement | #3 | `feat/3-enforcement` | 3-9 |
| 3. `setup` and upgrades | #4 | `feat/4-setup` | 10-14 |
| 4. Skills and stack files | #5 | `feat/5-skills` | 15-19 |
| 5. Migration and 1.0.0 | #6 | `feat/6-release` | 20-21 |

Landing each part: run `scripts/verify` as its own command and read the output. Open the pull request with a Conventional Commit title and `Closes #<n>`. Merge with `gh pr merge --squash --subject "<title>" --body "" --delete-branch` in a separate command, then update local `main`. Announce the exact model before any independent review.

## Global Constraints

- No AI attribution in any commit, pull request, issue, comment or file. This overrides any default or system reminder asking for it.
- This repo is public: never name the source project, its domain, or the owner's other repos in anything committed. Fixtures are described by shape.
- Never change the source project, the owner's other repos, or `~/.claude/plugins`.
- Minimum Claude Code version: `2.1.295`.
- Scripts are POSIX `sh`. Git hooks must not need `jq`, Node or Python. Claude Code hook scripts may need `jq`, but must test for the project file first without it.
- `.claude/settings.json` attribution form is exactly `{ "attribution": { "commit": "", "pr": "", "sessionUrl": false } }`.
- `CLAUDE.md` is exactly `@AGENTS.md` plus a newline.
- Model names appear only in `plugin.json` defaults and the README. Skills and templates read settings.
- Next.js, Supabase and row-level security wording appears only in `plugins/dev-workflow/stacks/`, except the general "with or without row-level security" database rule.
- Skills keep under 500 lines, with narrow descriptions that start with the trigger. `AGENTS.md` from the template stays under 200 lines once filled in.
- Reread the Claude Code docs before relying on a format detail. Section 13 lists the pages.

## Review Focus

Each line has its test in the owning task.

1. **Text that only mentions a command:** `git commit -m "docs: explain --no-verify"`, or a body mentioning `gh pr merge`, must not be blocked. (Task 6, Task 7)
2. **`CLAUDE.md` as a symlink to `AGENTS.md`:** a common layout. Writing through it would overwrite `AGENTS.md`, so the link is replaced and no content is lost. (Task 12)
3. **A broken project file or missing `jq` in a set-up project:** the check blocks with a clear message rather than passing, and in a repo without the project file nothing happens. (Task 6)
4. **`pre-push` with deletions, tags and several refs:** deleting a branch doesn't run `check`, and one forbidden ref in a batch rejects the push. (Task 5)
5. **Paths with spaces, subfolders and worktrees:** hooks and `setup` work in `/tmp/a b/repo`, from a subfolder, and where `.git` is a file. (Task 5, Task 6, Task 13)

---

## Part 1: Adopt in this repo (#2)

### Task 1: Test harness, `check` and `verify`

**Files:**
- Create: `.gitignore`, `tests/lib/assert.sh`, `tests/run.sh`, `scripts/check`, `scripts/verify`, `tests/harness.test.sh`, `tests/verify_only/leak.test.sh`
- Local only, git-ignored: `.leak-terms.local`

**Interfaces:**
- Produces, in `tests/lib/assert.sh`: `assert_exit <code> <cmd...>`, `assert_contains <text> <needle>`, `assert_not_contains <text> <needle>`, `assert_file_same <a> <b>`, `new_repo <dir>` (a `git init` with identity set and default branch `main`), `tmp_dir` (removed on exit).
- Produces: `tests/run.sh [dir]` runs every `*.test.sh` under `tests/`, skipping `tests/verify_only/`, each in its own process, printing a pass/fail count and exiting non-zero on any failure.
- Produces: `scripts/check` runs `tests/run.sh`, `claude plugin validate plugins/dev-workflow`, `claude plugin validate .`, and `uvx --from shellcheck-py shellcheck` over all shell files. A missing `uvx` or `claude` fails with its name. `scripts/verify` runs `check`, then `tests/verify_only/*.test.sh`.

- [ ] **Step 1: Write the failing test** in `tests/harness.test.sh`: `assert_exit 0 true` passes, `assert_exit 0 false` fails, `assert_contains "abc" "b"` passes, and `tests/run.sh` on a temp folder holding one failing `*.test.sh` exits non-zero and prints `1 failed`.
- [ ] **Step 2: Run it:** `sh tests/harness.test.sh`. Expected: fails because `tests/lib/assert.sh` is missing.
- [ ] **Step 3: Implement** `assert.sh` and `run.sh`, then `scripts/check` and `scripts/verify`. Write `.gitignore` with `.DS_Store`, `.leak-terms.local`, `plugins/*/evals/results/`, `.claude/settings.local.json`.
- [ ] **Step 4: Write the leak test** at `tests/verify_only/leak.test.sh`: it fails with a clear message when `.leak-terms.local` is missing, fails naming file and term when `plugins/dev-workflow` contains a term (case-insensitive, one term per line), and passes otherwise. Test it with temp folders and a temp term file through `LEAK_TERMS_FILE` and `LEAK_SEARCH_ROOT`.
- [ ] **Step 5: Draft `.leak-terms.local`** from the source project's `AGENTS.md`: its name, company and product names, domain nouns that aren't everyday software terms, and theme names. Confirm `git check-ignore .leak-terms.local` prints the path.
- [ ] **Step 6: Run** `scripts/check`, then `scripts/verify`. Expected: both pass. `claude plugin validate` may warn; only failures count.
- [ ] **Step 7: Commit:** `chore: add test harness, check and verify (#2)`.

### Task 2: This repo's own rules and starter hooks

**Files:**
- Create: `AGENTS.md`, `CLAUDE.md`, `docs/decisions.md`, `docs/maintenance.md`, `.claude/dev-workflow.json`, `.githooks/commit-msg`, `.githooks/pre-push`, `tests/repo.test.sh`
- Commit: the spec and this plan

**Interfaces:**
- Produces: starter hooks, replaced by the templates in Task 5.

- [ ] **Step 1: Write the failing test** in `tests/repo.test.sh`: `CLAUDE.md` equals `@AGENTS.md\n`; `AGENTS.md` under 200 lines and contains `Closes #`; `.githooks/commit-msg` on a temp file holding `bad message` exits 1, and on `chore: good (#2)` exits 0; `.githooks/commit-msg` rejects a message with a `Co-Authored-By: Claude` line.
- [ ] **Step 2: Run it:** `sh tests/repo.test.sh`. Expected: fails on the missing files.
- [ ] **Step 3: Implement.** `AGENTS.md` covers this repo: what it is, commands, layout, and the Appendix A rules that apply to a plugin repo, stated briefly. The decision log gets a line linking the spec. Run `git config core.hooksPath .githooks`. `AGENTS.md` says a fresh clone must run this.
- [ ] **Step 4: Run** `scripts/check`. Expected: pass.
- [ ] **Step 5: Commit:** `chore: adopt the methodology in this repo (#2)`.
- [ ] **Step 6: Ask the owner once** about applying the GitHub settings to this repo (squash only, blank message, pull request title as subject, delete merged branches). Don't wait on it: carry on, and apply when approved.
- [ ] **Step 7: Land #2,** add the plan link to #1, and update local `main`.

---

## Part 2: Enforcement (#3)

Paths are under `plugins/dev-workflow/`. Git hook templates live in `skills/setup/templates/githooks/`.

### Task 3: Shared git hook library and `commit-msg`

**Files:**
- Create: `skills/setup/templates/githooks/dw-lib.sh`, `skills/setup/templates/githooks/commit-msg`, `tests/githooks/commit-msg.test.sh`

**Interfaces:**
- Produces, in `dw-lib.sh`: `dw_has_attribution <file>` (exit 0 if found), `dw_issue_from_branch <branch>` (prints the number or nothing), `dw_load_env` (sources `dev-workflow.env` next to the hook, failing with a clear message if it's missing).
- Produces: env file contract for `.githooks/dev-workflow.env`: `DW_DEFAULT_BRANCH`, `DW_CHECK`, `DW_CI_ALLOWLIST` (newline-separated paths), `DW_FORMATTERS` (newline-separated `glob|command` lines). Generated by `setup` from the project file.

- [ ] **Step 1: Write the failing test.** Table of message, branch and expected exit:

| Message | Branch | Exit |
|---|---|---|
| `feat(api)!: add thing (#12)` | `feat/12-thing` | 0 |
| `fix: thing` | `feat/12-thing` | 1, names `#12` |
| `fix: thing` | `experiment` | 0 |
| `not conventional` | `experiment` | 1 |
| `Merge branch 'x'` | `experiment` | 1 |
| `fixup! feat: thing` | `feat/12-thing` | 0 |
| `feat: x (#12)` + `Co-Authored-By: Claude <noreply@anthropic.com>` | `feat/12-thing` | 1 |
| `feat: x (#12)` + `Generated with [Claude Code](...)` | `feat/12-thing` | 1 |
| `feat: x (#12)` + `Co-Authored-By: Ana Ruiz <ana@example.com>` | `feat/12-thing` | 0 |
| `fix: handle the Claude Code hook input (#12)` | `feat/12-thing` | 0 |

Comment lines starting with `#` in the message are ignored.

- [ ] **Step 2: Run it:** `sh tests/githooks/commit-msg.test.sh`. Expected: fails on the missing hook.
- [ ] **Step 3: Implement.** Attribution means a `Co-Authored-By` line naming an AI tool or an AI vendor's address, or a "generated with/by" or "written by" line naming one, or the robot emoji footer. Keep the tool list in one variable in `dw-lib.sh`. Conventional type list: `feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert`.
- [ ] **Step 4: Run it.** Expected: pass.
- [ ] **Step 5: Commit:** `feat(hooks): reject bad commit messages (#3)`.

### Task 4: `pre-commit`

**Files:**
- Create: `skills/setup/templates/githooks/pre-commit`, `tests/githooks/pre-commit.test.sh`

**Interfaces:**
- Consumes: `dw_load_env`, `DW_FORMATTERS`, `DW_CI_ALLOWLIST`.

- [ ] **Step 1: Write the failing test.** In a temp repo with a fake formatter script that exits 1 for files containing `BAD`:
  - staged `a.rs` containing `BAD` with `*.rs|./fmt` exits 1 and names the file;
  - staged `a.rs` clean exits 0;
  - staged `a.ts` with only a `*.rs` formatter exits 0;
  - two formatters each receive only their own files;
  - nothing staged exits 0;
  - a file named `a b.rs` reaches the formatter as one argument;
  - staged `.github/workflows/x.yml` with `on: pull_request` exits 1; with `on: { pull_request: {} }` exits 1; with `on: [push]` exits 1; with `on: workflow_dispatch` exits 0; listed in `DW_CI_ALLOWLIST` exits 0.
- [ ] **Step 2: Run it.** Expected: fails on the missing hook.
- [ ] **Step 3: Implement.** Read the staged version of workflow files (`git show :path`), not the working copy.
- [ ] **Step 4: Run it.** Expected: pass.
- [ ] **Step 5: Commit:** `feat(hooks): check staged formatting and CI triggers (#3)`.

### Task 5: `pre-push`, and replace this repo's starter hooks

**Files:**
- Create: `skills/setup/templates/githooks/pre-push`, `tests/githooks/pre-push.test.sh`
- Modify: `.githooks/*` to copies of the templates, plus `.githooks/dev-workflow.env`; add a test in `tests/repo.test.sh` that they match

**Interfaces:**
- Consumes: `dw_load_env`, `DW_CHECK`, `DW_DEFAULT_BRANCH`.

- [ ] **Step 1: Write the failing test,** feeding the hook its documented stdin (`local-ref local-sha remote-ref remote-sha`) against a bare remote:
  - pushing `feat/1-x` with a passing check exits 0; with a failing check exits 1;
  - empty `DW_CHECK` exits 1 and says none is configured;
  - pushing to `main` when the remote already has branches exits 1;
  - pushing `main` to an empty remote exits 0;
  - deleting a branch exits 0 without running the check;
  - a batch with `feat/1-x` and `main` exits 1;
  - a repo at `/tmp/a b/repo` works.
- [ ] **Step 2: Run it.** Expected: fails on the missing hook.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run it, then copy the templates into `.githooks/`.** Expected: pass, and `scripts/check` passes through the new hooks.
- [ ] **Step 5: Commit:** `feat(hooks): run check and protect the default branch on push (#3)`.

### Task 6: Hook common library and command splitter

**Files:**
- Create: `scripts/lib/common.sh`, `scripts/lib/split-command.awk`, `tests/hooks/common.test.sh`, `tests/hooks/split.test.sh`, `tests/lib/hook.sh`

**Interfaces:**
- Produces, in `common.sh`: `dw_gate` (exits 0 silently unless the project file exists at `$CLAUDE_PROJECT_DIR/.claude/dev-workflow.json`; after that requires `jq` and valid JSON, denying with a clear message otherwise), `dw_deny <reason>`, `dw_ask <reason>` (print the `hookSpecificOutput` JSON and exit 0), `dw_project <jq-filter>`.
- Produces: `split-command.awk` reads a command and prints one simple command per line. It respects single and double quotes, splits on `&&`, `||`, `;`, `|`, `|&`, `&` and newlines, skips heredoc bodies, treats `$(...)` contents as separate commands, and strips leading `VAR=value` words.
- Produces, in `tests/lib/hook.sh`: `bash_input <cmd>`, `tool_input <tool> <json>`, `decision_of <script> <json>`, which prints `deny`, `ask` or `none`.

- [ ] **Step 1: Write the failing tests.** Splitter table:

| Input | Output lines |
|---|---|
| `a && b` | `a`, `b` |
| `a; b \| c` | `a`, `b`, `c` |
| `git commit -m "x && y"` | one line |
| `git commit -m 'gh pr merge'` | one line |
| `A=1 B=2 npm test` | `npm test` |
| `echo $(npm test)` | includes `npm test` |
| `cat <<EOF` + `gh pr merge` + `EOF` + `&& b` handled as heredoc body skipped | no line starts `gh pr merge` |

Gate table: no project file and no `jq` on `PATH` gives `none`. Project file and no `jq` gives `deny`, mentioning `jq`. Malformed project file gives `deny`, naming the file. A project dir of `/tmp/a b/repo` works.

- [ ] **Step 2: Run them.** Expected: fail on the missing files.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run them.** Expected: pass.
- [ ] **Step 5: Commit:** `feat(hooks): add gate and command splitter (#3)`.

### Task 7: Bash rules

**Files:**
- Create: `scripts/hook-bash.sh`, `tests/hooks/bash.test.sh`

**Interfaces:**
- Consumes: `dw_gate`, `dw_deny`, `dw_ask`, `dw_project`, `split-command.awk`, `dw_has_attribution` from the template's `dw-lib.sh`.
- Project file fields: `commands.check`, `commands.verify`, `testCommands`, `databaseResetCommands`.

- [ ] **Step 1: Write the failing test.** In a repo with a project file setting `check` to `npm run check`, `testCommands` to `["npx vitest"]`, and `databaseResetCommands` to `["npm run db:reset"]`:

| Command | Decision |
|---|---|
| `git commit --no-verify -m "feat: x (#1)"` | deny |
| `git commit -n -m "feat: x (#1)"` | deny |
| `git push --no-verify` | deny |
| `git commit -m "docs: explain --no-verify (#1)"` | none |
| `git merge feat/1-x` on `main` | deny |
| `git merge main` on `feat/1-x` | none |
| `npm run check && gh pr merge 1 --squash --body ""` | deny |
| `npx vitest; gh pr merge 1 --squash --body ""` | deny |
| `npm run check` | none |
| `gh pr merge 1 --squash --subject "x" --body "" && git pull` | none |
| `gh pr merge 1 --squash` | deny, default message |
| `gh pr merge 1 --merge --body ""` | deny |
| `gh pr create --title "add stuff" --body "Closes #1"` | deny, title |
| `gh pr create --title "feat: x" --body "no keyword"` | deny, closing keyword |
| `gh pr create --title "feat: x" --body "Closes #1"` | none |
| `gh pr create --title "feat: x" --body "Closes #1\n\nGenerated with Claude Code"` | deny, attribution |
| `gh pr create --title "feat: x" --body-file b.md`, where `b.md` has an attribution line | deny |
| `gh issue create --title x --body "Generated with Claude Code"` | deny |
| `gh pr comment 1 --body "explains gh pr merge"` | none |
| `npm run db:reset` | ask |
| `DEBUG=1 npm run db:reset` | ask |
| `dropdb app` | ask |
| `docker compose down -v` | ask |
| `npm run db:migrate` | none |

- [ ] **Step 2: Run it.** Expected: fails on the missing script.
- [ ] **Step 3: Implement.** The always-on reset list is `dropdb` and `docker compose down -v`. Project and stack lists add to it. Read `gh` flags from the unsplit subcommand with quotes respected.
- [ ] **Step 4: Run it.** Expected: pass.
- [ ] **Step 5: Commit:** `feat(hooks): enforce merge, attribution and reset rules on commands (#3)`.

### Task 8: GitHub MCP and workflow edit rules

**Files:**
- Create: `scripts/hook-github-mcp.sh`, `scripts/hook-workflow-edit.sh`, `tests/hooks/mcp.test.sh`, `tests/hooks/workflow.test.sh`

**Interfaces:**
- Consumes: `dw_gate`, `dw_deny`, `dw_ask`, `dw_project`, `dw_has_attribution`.

- [ ] **Step 1: Confirm the GitHub MCP tool and field names** by reading its current tool list (Spec section 14), and record them in a comment in the test.
- [ ] **Step 2: Write the failing tests.**
  - MCP: any string field with attribution on a create or update tool gives deny; a merge tool without squash and an empty message gives deny; a clean create gives none; a read tool gives none.
  - Workflow: Write of `.github/workflows/x.yml` containing `pull_request` gives ask; Edit whose `new_string` adds `push:` under `on:` gives ask; `workflow_dispatch` only gives none; a file in `ciAllowlist` gives none; a Write outside `.github/workflows/` gives none; a file whose text only mentions "push" in a step name gives none.
- [ ] **Step 3: Run them.** Expected: fail on the missing scripts.
- [ ] **Step 4: Implement.**
- [ ] **Step 5: Run them.** Expected: pass.
- [ ] **Step 6: Commit:** `feat(hooks): enforce rules on GitHub tools and workflow edits (#3)`.

### Task 9: Register hooks, session-start check, settings and live tests

**Files:**
- Create: `hooks/hooks.json`, `scripts/hook-session-start.sh`, `tests/hooks/session-start.test.sh`, `tests/verify_only/live-hooks.test.sh`, `docs/hook-behaviour.md`
- Modify: `.claude-plugin/plugin.json` (add author and the `userConfig` from spec section 6, with exactly those keys and defaults; add `description`)

**Interfaces:**
- Produces: `hooks.json` runs the four scripts in exec form with `${CLAUDE_PLUGIN_ROOT}` and `"onFailure": "block"` on PreToolUse handlers. Matchers: `Bash`, `Write|Edit`, and the MCP pattern from Task 8. `SessionStart` has a timeout and doesn't block.

- [ ] **Step 1: Write the failing test.** Session start, in a repo with a project file: all well gives empty output; `core.hooksPath` unset gives one line naming the fix; a stale `pluginVersion` gives one line; `docs/maintenance.md`'s last date older than `CLAUDE_PLUGIN_OPTION_MAINTENANCE_INTERVAL_DAYS` gives one line naming `/dev-workflow:maintain`; a missing tool or plugin gives one line with its install command. No project file gives empty output and exit 0, with no `jq`.
- [ ] **Step 2: Run it.** Expected: fails on the missing script.
- [ ] **Step 3: Implement.** Read `~/.claude/plugins/installed_plugins.json` directly rather than calling `claude`. Test the speed: under 1 second in the fixture.
- [ ] **Step 4: Run it, then `claude plugin validate plugins/dev-workflow`.** Expected: pass.
- [ ] **Step 5: Write the live test** with `claude -p --plugin-dir plugins/dev-workflow` in a temp repo with a project file, using `--max-budget-usd` or the current equivalent. It records whether:
  - a chained merge is blocked,
  - a `git commit --no-verify` is blocked,
  - `"ask"` on `npm run db:reset` is denied without a person,
  - a broken script blocks under `onFailure`,
  - the same commands run freely in a repo without a project file.
- [ ] **Step 6: Run it** as its own command, and read the output. Check `"ask"` under auto mode by hand in a session if `-p` can't show it. Write the results to `docs/hook-behaviour.md`. If `"ask"` passes anywhere without a person, change the reset rule to deny, with a project-level way to allow it, as the spec says.
- [ ] **Step 7: Commit:** `feat(hooks): register hooks and add the session-start check (#3)`.
- [ ] **Step 8: Land #3.**

---

## Part 3: `setup` and upgrades (#4)

### Task 10: Legacy texts and repo detection

**Files:**
- Create: `skills/setup/references/legacy/` (one file per published text), `scripts/setup/detect.sh`, `tests/setup/detect.test.sh`, `tests/setup/legacy.test.sh`

**Interfaces:**
- Produces: `detect.sh <root>` prints JSON: `{ "repo": "empty|existing", "git": bool, "remote": "github|other|none", "defaultBranch": str, "stackHints": [], "hookTool": "husky|lefthook|none|<name>", "agents": bool, "claude": "absent|import|pointer|content|symlink", "legacyBlocks": ["web-5","web-6","issues"], "projectFile": bool }`.
- Produces: `legacy/` files, named `web-5.<section>.md`, `web-6.<section>.md`, `issues.md`, `pointer-*.md`, holding exact published texts.

- [ ] **Step 1: Write the failing test** `legacy.test.sh`: for every commit in `git log -- plugins/web-dev-workflow/skills/setup/SKILL.md plugins/dev-workflow/commands/enable-github-issues.md` (`de3a6b4`, `f4694d3`, `17416e9`, `fd04f50`), the fenced rule block and the pointer text at that commit are found in `legacy/`. It reads those commits with `git show`, so it keeps working after the old paths are deleted.
- [ ] **Step 2: Write the failing test** `detect.test.sh`, one case per field value above, building temp repos.
- [ ] **Step 3: Run them.** Expected: fail.
- [ ] **Step 4: Extract the legacy texts** from git history into `legacy/`, and implement `detect.sh`.
- [ ] **Step 5: Run them.** Expected: pass.
- [ ] **Step 6: Commit:** `feat(setup): recognise old setups and detect repo state (#4)`.

### Task 11: Managed sections and ledger

**Files:**
- Create: `skills/setup/templates/agents/{project,decisions,workflow,testing,tools,models,communication}.md`, `scripts/setup/agents-md.sh`, `scripts/setup/ledger.sh`, `tests/setup/agents-md.test.sh`, `tests/setup/template.test.sh`

**Interfaces:**
- Produces: `ledger.sh get|set <project-file> <key> [hash]`, and `ledger.sh hash <file>` using `git hash-object`.
- Produces: `agents-md.sh plan|apply <root> <templates-dir>`, printing one JSON line per section: `{ "section": str, "action": "create|update|keep|conflict", "diff": str? }`. Markers are `<!-- dev-workflow:begin <section> -->` and `<!-- dev-workflow:end <section> -->`. Ledger keys are `AGENTS.md#<section>`.

- [ ] **Step 1: Write the failing tests.**
  - New file: all sections are written, in order, and the file is under 200 lines with the prompts filled by sample text.
  - Rerun: every section reports `keep`, and the file is byte-identical.
  - Plugin text changed, section untouched: `update`.
  - Section edited by the project: `conflict`, the edit stays, and the diff is shown.
  - Text outside markers is byte-identical after `apply`.
  - Old block `web-6` exact: replaced, with its headings gone.
  - Old block with one subsection edited: the edited subsection is kept and reported, and the rest is replaced.
  - `issues` block in `AGENTS.md`: replaced.
  - Old block in `CLAUDE.md`: handled together with Task 12's migration.
  - CRLF line endings and a missing final newline in `AGENTS.md`: content is kept.
  - Template test: templates name no models, no stack products, and contain the overrides from spec section 10.
- [ ] **Step 2: Run them.** Expected: fail.
- [ ] **Step 3: Write the templates** from Appendix A and spec section 10. Short rules only, with detail left to skills. The Models section states the routing rule and points to the plugin's settings in `/config`.
- [ ] **Step 4: Implement** `ledger.sh` and `agents-md.sh`.
- [ ] **Step 5: Run them.** Expected: pass.
- [ ] **Step 6: Commit:** `feat(setup): manage AGENTS.md sections without overwriting edits (#4)`.

### Task 12: `CLAUDE.md`, settings, project file and hook install

**Files:**
- Create: `scripts/setup/claude-md.sh`, `scripts/setup/settings.sh`, `scripts/setup/project-file.sh`, `scripts/setup/install-hooks.sh`, `skills/setup/references/project-file.schema.json`, `tests/setup/files.test.sh`

**Interfaces:**
- Consumes: `ledger.sh`, the env contract from Task 3, templates from Tasks 3-5.
- Produces: `project-file.sh write <root> <answers.json>` and `project-file.sh validate <file>`. It also generates `.githooks/dev-workflow.env`. `commands.formatCheckStaged` is an array of `{ "glob": str, "command": str }`.

- [ ] **Step 1: Write the failing tests.**
  - `CLAUDE.md`: absent gives the import; old pointer gives the import; content is moved to `AGENTS.md` first and nothing is lost; a symlink to `AGENTS.md` is replaced by a regular file and `AGENTS.md` keeps its bytes; rerun changes nothing.
  - Settings: no file gives the exact attribution form; an existing file with other keys keeps them; invalid JSON stops with an error and leaves the file alone; rerun is byte-identical. The `gh pr merge` permission goes in `settings.local.json` only when approved, and doesn't duplicate.
  - Project file: `check` missing gives a validation error; a mixed repo with two formatters round-trips into the env file; values with quotes and spaces survive into the env file and source correctly.
  - Hooks: a `package.json` gets a `prepare` script and existing scripts are kept; no `package.json` sets `core.hooksPath`; husky adds a call in `.husky/` without replacing existing lines; lefthook is reported with the lines to add; an edited hook is left alone and reported as a conflict.
- [ ] **Step 2: Run them.** Expected: fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run them.** Expected: pass.
- [ ] **Step 5: Commit:** `feat(setup): write the import, settings, project file and hooks (#4)`.

### Task 13: `setup` entry point, tools check, GitHub settings and the skill

**Files:**
- Create: `scripts/setup/run.sh`, `scripts/setup/tools.sh`, `scripts/setup/github-settings.sh`, `tests/setup/run.test.sh`, `skills/setup/SKILL.md` (rewrite)
- Delete: nothing yet. `plugins/web-dev-workflow/` goes in Task 20.
- Move: new `setup` lives in `plugins/dev-workflow/skills/setup/`; delete `plugins/dev-workflow/commands/enable-github-issues.md`

**Interfaces:**
- Produces: `run.sh --root <dir> --answers <file> --plan|--apply`. Plan prints JSON lines `{ "path": str, "action": "create|update|keep|conflict", "detail": str }` and writes nothing. Apply stops before writing anything if the required tools fail.
- Produces: `tools.sh` prints JSON: `{ "required": [...], "plugins": [...], "other": [...] }`, each with `name`, `present`, `install`. It reads `installed_plugins.json`, checks for the Superpowers skills the methodology names, and compares the Claude Code version with `2.1.295`.
- Produces: `github-settings.sh <owner/repo>`, using the current GitHub API fields, confirmed before use: squash merge only, title from the pull request, blank message, delete merged branches. It's run only with approval.

- [ ] **Step 1: Write the failing tests.**
  - `--plan` writes nothing (`git status --porcelain` unchanged, with the tree hashed).
  - `--apply` on an empty dir creates everything in spec section 7, step 5, except approved-only items.
  - A second `--apply` reports only `keep`, and the tree hash is unchanged.
  - A path with spaces and a run from a subfolder both work.
  - Where `.git` is a file (a worktree), hooks install correctly.
  - `tools.sh` with a stubbed `PATH` reports `jq` missing with its install command.
  - A Claude Code version below the minimum stops `--apply`.
- [ ] **Step 2: Run them.** Expected: fail.
- [ ] **Step 3: Implement the scripts.**
- [ ] **Step 4: Write `SKILL.md`** as spec section 7's flow: detect, tools, ask one question at a time with a recommendation, show the plan, get a yes, apply, report. Use `${CLAUDE_PLUGIN_ROOT}/scripts/setup/`. `allowed-tools` covers those scripts plus Read and Bash for detection. Hand to `choose-stack` if no stack is decided.
- [ ] **Step 5: Run the tests.** Expected: pass.
- [ ] **Step 6: Commit:** `feat(setup): add the setup entry point and skill (#4)`.

### Task 14: The two test setups

**Files:**
- Create: `tests/fixtures/{next-supabase,litestar-postgres}/` (two setups since 2026-11-05; see the spec), `tests/verify_only/fixtures.test.sh`, plus answers files per fixture

**Interfaces:**
- Consumes: `run.sh`.
- Each fixture: a small real app with real `check` and `verify` commands and a known answers file. Copied to a temp folder for each run.

- [ ] **Step 1: Write the failing test.** For each fixture and each starting state in spec section 11: copy it, `run.sh --apply`, then:
  - `CLAUDE.md` is the import, and `AGENTS.md` has every managed section;
  - an old block, when present, is gone;
  - a bad commit is rejected;
  - a good commit passes;
  - `pre-push` runs the real `check`, and it passes;
  - a second apply changes nothing;
  - a project edit survives a rerun.

  Next.js with Supabase also runs one real row-level security test, and Litestar one real data-access test against Postgres in Docker. Docker not running fails with that message. Old-setup starting states are seeded from the `legacy/` texts.

- [ ] **Step 2: Run it.** Expected: fails on the missing fixtures.
- [ ] **Step 3: Build the fixtures,** smallest working apps at verified latest stable versions. Supabase comes through the fixture's dev dependency. Rust has a server crate and a `ui/` folder with two formatters.
- [ ] **Step 4: Run it** as its own command, and read the output. Expected: pass. It may take minutes.
- [ ] **Step 5: Commit:** `test(setup): cover four stacks end to end (#4)`.
- [ ] **Step 6: Land #4.** Confirm by reading the fixtures output that Litestar and Rust ran with no stack file.

---

## Part 4: Skills and stack files (#5)

Each skill's body comes from the spec section named in its task. Evals are in Task 19.

### Task 15: `land` and `independent-review`

**Files:**
- Create: `skills/land/SKILL.md`, `skills/independent-review/SKILL.md`, `tests/skills/content.test.sh`

**Interfaces:**
- Consumes: `${user_config.reviewer_command}`, `${user_config.reviewer_name}`, `${user_config.review_threshold_lines}`.
- Produces: `tests/skills/content.test.sh`, a table of skill and required strings, extended by later tasks. It also checks every skill: frontmatter parses, description under 300 characters, body under 500 lines, no model names, and no stack words.

- [ ] **Step 1: Write the failing test.** `land` contains `--squash`, `--body ""`, `--delete-branch`, `Closes #`, and the ask-first rule; it says verify runs as its own command and never chained, and that a blocked merge means stop and ask. `independent-review` contains `${user_config.reviewer_command}`, tells the agent to announce `${user_config.reviewer_name}` before calling it, requires checking each finding against the code, and names what to do when Codex is missing.
- [ ] **Step 2: Run it.** Expected: fails.
- [ ] **Step 3: Write both skills** from spec sections 9 and 9.1.
- [ ] **Step 4: Run it.** Expected: pass. Also check with a `--plugin-dir` session that `${user_config.*}` is substituted in the skill body.
- [ ] **Step 5: Commit:** `feat(skills): add land and independent-review (#5)`.

### Task 16: `screen-check` and conventions

**Files:**
- Create: `skills/screen-check/SKILL.md`, `skills/conventions-code/SKILL.md`, `skills/conventions-ui/SKILL.md`, reference files where a body would pass 150 lines
- Modify: `tests/skills/content.test.sh`

- [ ] **Step 1: Extend the test.** `screen-check` contains `360`, `dark`, `keyboard`, and what to do with no browser tool. `conventions-code` contains every Code rule's key words from Appendix A, both data-layer routes (with and without row-level security), and "page by a unique key". `conventions-ui` contains `4.5:1`, `3:1`, `360`, `16 px`, `40 px`, "Never say it twice", and "(optional)".
- [ ] **Step 2: Run it.** Expected: fails.
- [ ] **Step 3: Write them.** Module shape stays in general words, and stack files map it.
- [ ] **Step 4: Run it.** Expected: pass.
- [ ] **Step 5: Commit:** `feat(skills): add screen-check and conventions (#5)`.

### Task 17: `choose-stack` and stack files

**Files:**
- Create: `skills/choose-stack/SKILL.md`, `stacks/node-tooling.md`, `stacks/nextjs.md`, `stacks/astro.md`, `stacks/supabase.md`, `tests/skills/stack-words.test.sh`
- Modify: `tests/skills/content.test.sh`, `skills/setup/SKILL.md` (read only the chosen stack files)

- [ ] **Step 1: Write the failing test.** `stack-words.test.sh`: stack product names appear only under `stacks/`. `choose-stack` contains where it runs, who operates it, data limits, licences, PoC and production, and names no vendor. Each stack file contains the `check` and `verify` shape and, for Supabase, `databaseResetCommands`.
- [ ] **Step 2: Run it.** Expected: fails.
- [ ] **Step 3: Write them.** Read current docs through Context7 for each stack file, and verify versions. General public guidance only.
- [ ] **Step 4: Run it.** Expected: pass.
- [ ] **Step 5: Commit:** `feat(skills): add choose-stack and stack files (#5)`.

### Task 18: `maintain` and `enable-releases`

**Files:**
- Create: `skills/maintain/SKILL.md`, `scripts/maintain/merged-branches.sh`, `skills/enable-releases/SKILL.md`, `skills/enable-releases/templates/`, `tests/maintain/branches.test.sh`
- Delete: `commands/enable-releases.md`
- Modify: `tests/skills/content.test.sh`

**Interfaces:**
- Produces: `merged-branches.sh <root>` prints `<branch> delete|keep <reason>` lines. It takes the pull request data from `gh pr list --state merged --json headRefName,headRefOid,baseRefName`, deleting only a branch merged into the default branch, stubbed in tests through `DW_GH`.

- [ ] **Step 1: Write the failing test.** A local branch whose tip matches a merged pull request gives `delete`. Remote gone but no merged pull request gives `keep`. Tip ahead of the merged pull request gives `keep`. The current branch and default branch are always `keep`. A worktree's branch is listed with its worktree. `maintain` has `disable-model-invocation: true` and names all six areas and `docs/maintenance.md`. `enable-releases` has `disable-model-invocation: true`, its template has `workflow_dispatch` and no `push` trigger, it adds the optional check to `ciAllowlist`, and it says to verify the action's current version.
- [ ] **Step 2: Run it.** Expected: fails.
- [ ] **Step 3: Implement** from spec section 9.2, and carry over today's release-type detection.
- [ ] **Step 4: Run it.** Expected: pass.
- [ ] **Step 5: Commit:** `feat(skills): add maintain and manual releases (#5)`.

### Task 19: Skill evals

**Files:**
- Create: `evals/<skill>-fires/{prompt.md,graders/*.md}` and `evals/<skill>-quiet/{prompt.md,graders/*.md}`

**Interfaces:**
- A fire case: `tool_used` on `Skill` with `input_match: '"skill"\s*:\s*"(?:[\w-]+:)?<skill>"'`. A quiet case: the same with `min: 0`, `max: 0`. Manual skills (`maintain`, `enable-releases`) get quiet cases only, with prompts naming their topic.

- [ ] **Step 1: Write the cases.** Natural phrasing, not naming the skill:

| Skill | Fires on | Stays quiet on |
|---|---|---|
| `setup` | "Starting a new web app in this empty repo, set up how we work" | "Fix the typo in the README" |
| `choose-stack` | "We need a database and hosting for a client portal, what should we use?" | "Add a date column to this table" |
| `land` | "Tests pass, this work is done, get it in" | "Run the tests" |
| `independent-review` | "Get an outside review of this large pull request" | "What does this function do?" |
| `screen-check` | "I changed the settings page, make sure it looks right" | "Refactor this SQL query" |
| `conventions-code` | "Where should this new query and its permission check live?" | "Change this button's colour" |
| `conventions-ui` | "Write the labels and tooltips for this form" | "Speed up this database query" |
| `maintain` | none | "Clean up this function" |
| `enable-releases` | none | "Explain what SemVer is" |

- [ ] **Step 2: Run** `claude plugin eval plugins/dev-workflow --max-cost-usd 15` as its own command, and read the results. If eval is unavailable, use the skill-creator tooling and say so.
- [ ] **Step 3: Tighten descriptions** where a case fails, and rerun only those cases with `--case`. Report any case that stays unreliable rather than dropping it.
- [ ] **Step 4: Commit:** `test(skills): add trigger and quiet evals (#5)`.
- [ ] **Step 5: Land #5,** with the independent review, and report the eval results.

---

## Part 5: Migration and 1.0.0 (#6)

### Task 20: Marketplace, removal and version

**Files:**
- Modify: `.claude-plugin/marketplace.json`, `plugins/dev-workflow/.claude-plugin/plugin.json`
- Delete: `plugins/web-dev-workflow/`
- Create: `tests/verify_only/install.test.sh`, `tests/marketplace.test.sh`

- [ ] **Step 1: Write the failing tests.** Marketplace: no `web-dev-workflow` entry, `renames` is exactly `{ "web-dev-workflow": "dev-workflow" }`, `dev-workflow` has author and description, `version` only in `plugin.json`, and it's `1.0.0`. Install test, in an isolated `CLAUDE_CONFIG_DIR`:
  - install from a local marketplace copy;
  - a machine with old `web-dev-workflow` moves to `dev-workflow`, including the "not cached" case;
  - a machine with old `dev-workflow` 0.2.0 updates;
  - the components list shows nine skills and no duplicates;
  - a project's `enabledPlugins` key gets rewritten.
- [ ] **Step 2: Run them.** Expected: fail.
- [ ] **Step 3: Make the changes.** If the move from 1.2.0 to 1.0.0 fails as a downgrade, use `2.0.0` and tell the owner.
- [ ] **Step 4: Run** `claude plugin validate . --strict`, `claude plugin validate plugins/dev-workflow --strict`, and the tests. Expected: pass, with any directory-only warnings noted.
- [ ] **Step 5: Commit:** `feat!: release dev-workflow 1.0.0 and remove web-dev-workflow (#6)`, with a `BREAKING CHANGE:` footer naming the removed commands.

### Task 21: README, final verification and handover

**Files:**
- Modify: `README.md`, `AGENTS.md`, `docs/decisions.md`
- Create: `tests/readme.test.sh`

- [ ] **Step 1: Write the failing test.** The README contains the three update commands in spec section 12, every `userConfig` key, "how to change a default", every upgrade note in section 12, the skills table, and neither `/web-dev-workflow:` as a current command nor `enable-github-issues` except in the upgrade notes.
- [ ] **Step 2: Run it.** Expected: fails.
- [ ] **Step 3: Write the README.**
- [ ] **Step 4: Run `scripts/verify`** as its own command, and read every result, including the leak and stack-word searches. Then announce and run the independent review on the whole branch of changes in this part.
- [ ] **Step 5: Commit:** `docs: explain install, update and settings (#6)`.
- [ ] **Step 6: Land #6,** confirm #1 closes, and update local `main`.
- [ ] **Step 7: Report to the owner:** what landed, what was verified with its results, the update commands to run, which repos still hold old blocks (by name, in chat only), and anything skipped or failed.

## Spec coverage

| Spec section | Tasks |
|---|---|
| 5 Layout | 13, 15-18, 20 |
| 6 Settings | 9, 12 |
| 7 `setup` | 10-14 |
| 8 Enforcement | 3-9 |
| 9 Skills | 13, 15-18 |
| 10 Template and stacks | 11, 17 |
| 11 Testing | 1, 3-9, 14, 19, 20 |
| 12 Migration and this repo | 1-2, 20-21 |
