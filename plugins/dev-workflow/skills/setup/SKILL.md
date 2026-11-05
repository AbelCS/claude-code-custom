---
name: setup
description: Setting up or upgrading a repo with the dev-workflow methodology, or starting a new web project. Detects the repo, checks the tools, asks what it can't detect one question at a time, shows the plan, and writes only after a yes.
allowed-tools: Read Glob Grep Bash(sh ${CLAUDE_PLUGIN_ROOT}/scripts/setup/detect.sh *) Bash(sh ${CLAUDE_PLUGIN_ROOT}/scripts/setup/tools.sh *) Bash(sh ${CLAUDE_PLUGIN_ROOT}/scripts/setup/run.sh *) Bash(sh ${CLAUDE_PLUGIN_ROOT}/scripts/setup/project-file.sh existing-ci *) Bash(git status *) Bash(git remote *) Bash(git log *) Bash(ls *)
---

# Setup

Say "Using setup to ..." first. The scripts in `${CLAUDE_PLUGIN_ROOT}/scripts/setup/` do the mechanical work: fingerprints, moving old text, JSON merges and installing hooks. This skill holds the judgment: what to ask, and how to explain what the scripts found.

**Nothing is written before the person says yes to the plan.** That includes the answers, which go to `run.sh` on stdin rather than into a file.

## 1. Detect

Run `sh ${CLAUDE_PLUGIN_ROOT}/scripts/setup/detect.sh .` from the repo. It prints JSON: whether the repo is empty, its remote and default branch, stack hints and other languages, any hook tool already there (husky, lefthook, pre-commit, simple-git-hooks), the hooks path git uses and where it's set (`hooksPath`, `hooksPathScope`), the executable hooks in `.git/hooks` (`gitHooks`), the state of `AGENTS.md` and `CLAUDE.md`, the old rule blocks found in them, and whether there's a project file.

Read what you need to answer the questions yourself: `package.json` scripts, `pyproject.toml`, a `Makefile`, the CI workflows, an existing `.claude/dev-workflow.json`. An answer you can read is one you don't have to ask.

## 2. Check the tools

Run `sh ${CLAUDE_PLUGIN_ROOT}/scripts/setup/tools.sh .` and report each tool as present or missing, with its exact `install` command.

- **`required`** (git, gh signed in, jq, Claude Code 2.1.295 or later): if any is missing, stop here. Give the install commands and say to run setup again afterwards.
- **`plugins`**: offer to install the missing ones. Those with `"when": "screens"` matter only for a project with screens. If superpowers lists `missingSkills`, say which skills the methodology names that it no longer has, and that the steps relying on them will need another way.
- **`other`**: Codex for independent review, and a browser for screen checks. A missing one means that step warns when it runs. Say so; never present it as fine.

## 3. Ask what it can't detect

One question at a time, each with your recommendation first and why. Skip any whose answer you already read. In this order:

1. **The stack.** Confirm `stackHints`. If no stack has been decided, as in a new project, hand over to `/dev-workflow:choose-stack` and continue once it is. Then read only the chosen stacks' files, `${CLAUDE_PLUGIN_ROOT}/stacks/<name>.md` for each name in `stack`, and no others.
2. **The commands:** `check` is required, as `pre-push` runs it. Then `verify`, formatting checks for staged files, and the optional ones. `references/answers.md` lists them, and the stack files say how their stack fills them. With no stack file, ask for each.
3. **Screens:** whether people use screens in it.
4. **A database,** with or without row-level security, and its reset commands, if any.
5. **The default branch,** only when there's no remote to read it from.
6. **Per-PR workflows:** if `sh ${CLAUDE_PLUGIN_ROOT}/scripts/setup/project-file.sh existing-ci .` lists any, ask which stay, for `ciAllowlist`. Recommend none: CI runs only for releases.
7. **Approvals,** each its own question:
   - `mergePermission`: let the agent merge its own green pull requests in auto mode. Recommend yes.
   - `githubSettings`: only with a GitHub remote. Squash merges only, the pull request's title as the subject, a blank message, merged branches deleted. Recommend yes. It changes that repo's settings, so name the repo.
   - `installPlugins`: only if plugins are missing. Name them.
   - `moveGitHooks`: only if `gitHooks` lists any, `hooksPathScope` is null and `hookTool` is `none`. Name them, and say that turning on the dev-workflow hooks would stop them running. Moving them puts each into `.githooks`: `pre-commit`, `commit-msg` and `pre-push` as `<name>.local`, which the dev-workflow hook of that name runs first, and any other under its own name. Recommend yes. With no, the dev-workflow hooks stay off until the person moves or removes them by hand and runs setup again.

## 4. Show the plan

Build the answers as `references/answers.md` describes, then run:

```sh
sh ${CLAUDE_PLUGIN_ROOT}/scripts/setup/run.sh --root . --plan --answers - <<'ANSWERS'
{ ... }
ANSWERS
```

It prints one JSON line per path: `create`, `update`, `keep` or `conflict`, with a `detail`. It writes nothing. Show it grouped by action, in plain words:

- what will be created and updated, and what's already right;
- old rule blocks being replaced (`AGENTS.md#legacy:...`) and text moving from `CLAUDE.md`, which is never dropped;
- every conflict: a part the project edited, which stays as it is, with the difference from the plugin's text, or something setup can't do, with why.
- a `core.hooksPath` conflict: git already runs hooks from another folder, set in this repo or in the person's own git config (`hooksPathScope` says which). Setup never sets `.githooks` over it, as that would stop those hooks here. Show the lines its detail gives, to add to the hooks there. For a global or system one, also say that `git config core.hooksPath .githooks` in this repo would run only this repo's hooks here. Leave that choice to the person, and don't run it for them.

Then ask for a yes. A change to the answers means a new plan.

## 5. Apply

After the yes, run the same command with `--apply` instead of `--plan`, and the same answers. Exit 1 means a required tool went missing since the check: report it, and stop. Exit 2 is an error: show its message, and don't retry blindly.

## 6. Report

Lead with the outcome. Then, from what `--apply` printed:

- **Written and updated:** the files and settings, briefly.
- **Migrated:** old blocks replaced, text moved from `CLAUDE.md`, old pointers replaced by the import.
- **Left alone:** each conflict, and what to do about it if anything.
- **Still missing:** tools, plugins, Superpowers skills and other tools from step 2, with their install commands. After installing plugins, `/reload-plugins`.
- **Next:** fill in the `_Fill in:_` parts of `AGENTS.md`'s project section, if it was new. Commit the setup on a branch, the methodology's way.
- **A fresh clone:** git hooks aren't cloned, so say how to turn them on there. With a `prepare` script in `package.json` (`package.json` updated), `npm install` does it. Otherwise `git config core.hooksPath .githooks`. With husky or lefthook, that tool's own install.

A rerun with nothing changed reports only `keep`: say so plainly.
