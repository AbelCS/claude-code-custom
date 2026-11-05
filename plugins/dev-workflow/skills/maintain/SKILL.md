---
name: maintain
description: Run by a person when maintenance is due, or the session start says it's overdue. Sweeps merged branches, dead code, dependencies, code smells, docs and the methodology's setup, lands each area's fixes through its own issue and pull request, and records the run in docs/maintenance.md.
disable-model-invocation: true
allowed-tools: Read Glob Grep Bash(sh ${CLAUDE_PLUGIN_ROOT}/scripts/maintain/merged-branches.sh *) Bash(sh ${CLAUDE_PLUGIN_ROOT}/scripts/setup/detect.sh *) Bash(sh ${CLAUDE_PLUGIN_ROOT}/scripts/setup/tools.sh *) Bash(sh ${CLAUDE_PLUGIN_ROOT}/scripts/setup/run.sh * --plan *) Bash(git status *) Bash(git log *) Bash(git worktree list *)
---

# Maintain

Say "Using maintain to ..." first. A person starts this; it never runs on a schedule. The session-start check says when it's due: every `${user_config.maintenance_interval_days}` days after the last run in `docs/maintenance.md`. If that setting shows as a `user_config` placeholder rather than a value, it was never saved: use its `default` from `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json`, and say so.

## How the work lands

- **Start from a clean, updated default branch.** Read `defaultBranch` from `.claude/dev-workflow.json`, `main` when missing. `git status --porcelain` must print nothing: if it doesn't, stop and ask, and never stash or discard someone's work. Then `git switch <default>` and `git pull --ff-only`.
- **One issue and one squash-merged pull request per area** that changes files, the methodology's usual way: an issue with objective, scope and acceptance criteria, a `<type>/<issue>-<slug>` branch, test first, `verify` as its own command, then `/dev-workflow:land`. Back on the updated default branch before the next area. An area with nothing to change gets no issue.
- **Anything that alters what people see or do, money rules or permissions waits for approval.** Raise its issue, say what you'd change, and leave it for the owner.
- **The last run's date** is the last line of `docs/maintenance.md`. "Since the last run" means since that date. With no earlier run, use the last `${user_config.maintenance_interval_days}` days, and say so.

## 1. Branches

Run `sh ${CLAUDE_PLUGIN_ROOT}/scripts/maintain/merged-branches.sh .`. It prints `<branch> delete|keep <reason>` a line, and changes nothing. Only `delete` is proven: a pull request from that branch was merged at exactly its tip.

For each `delete`:

1. If its reason names a worktree, `git worktree remove <path>`, never --force. If git refuses, as it does with uncommitted changes there, keep the branch and list it with why.
2. `git branch -D <branch>`. A squash merge looks unmerged to `git branch -d`, which is why the script asked GitHub.

Then `git worktree prune` and `git fetch --prune`. List everything else for a decision, with each reason, and delete none of it without the owner's word. If the script fails, as when gh isn't signed in, report it and delete nothing. Branches change no files, so this area needs no issue.

## 2. Dead code

Run the project's `deadCode` command. If none is configured, say so, and point to the stack file or the Commands section of `AGENTS.md` as where to add one. Check each finding before removing it: search for uses the tool can't see, such as names built at run time, config files and entry points. Remove what's truly unused, with `verify` proving nothing broke.

## 3. Dependencies

- List what's behind, with the stack's own tool.
- The target is the latest stable version, verified from the registry or the release page, never remembered. Skip pre-releases.
- Read the migration guide before every major upgrade, through Context7 or the official docs, and do one major upgrade at a time, each with its own `verify`.
- Run the project's `audit` command. If none is configured, say so. Fix what it reports, or say why a finding can't be fixed yet.

## 4. Code smells

Limited to code changed since the last run: `git log --since=<date> --name-only --format= | sort -u` lists the files.

- Oversized files, split along the module shape in `/dev-workflow:conventions-code`.
- Duplication, and a rule computed in two places with no parity test.
- Broken boundaries: a module reaching past another's contracts, or ui reading the database.

Run `/simplify` and `/code-review` on those files, and check each finding against the code before acting on it. Behaviour stays the same: tests first where they're missing.

## 5. Docs

- `AGENTS.md`, the README and the decision log against the code: commands, layout, glossary and decisions that drifted.
- Finished plans in `docs/superpowers/plans/`: work that has landed, with its issue closed. Mark each finished at its top.
- Issues met but still open: check each one's acceptance criteria against the code. Close those met, with a comment naming the pull request that met them. Leave the rest, saying what's missing.

## 6. Methodology

Rerun the `setup` check. `sh ${CLAUDE_PLUGIN_ROOT}/scripts/setup/tools.sh .` for missing tools and plugins, then `run.sh` with `--plan` and `{}` as the answers, which writes nothing:

```sh
sh ${CLAUDE_PLUGIN_ROOT}/scripts/setup/run.sh --root . --plan --answers - <<'ANSWERS'
{}
ANSWERS
```

If it shows only `keep`, the setup is current. Otherwise run `/dev-workflow:setup` for what it lists, in this area's pull request.

## 7. Record the run

Add one line to the end of `docs/maintenance.md`, in exactly the form `- YYYY-MM-DD: what was done`, with today's date from `date +%Y-%m-%d`. The session-start check reads the date from the start of that line. Say briefly what each area did, as in `- 2026-12-06: Deleted 4 merged branches. Removed unused exports. Upgraded 3 dependencies. Docs and setup current.`

The line goes in the last area's pull request. If no area changed files, it lands in a pull request of its own, with its own issue.

## 8. Report

Lead with the outcome: each area, what it found and what landed, by pull request. Then the branches kept and why, the issues waiting for the owner's approval, and what was skipped or couldn't run, such as a missing `deadCode` or `audit` command.
