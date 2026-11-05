---
name: enable-releases
description: Run by a person, to set up release-please in a GitHub repo. Detects the release type and version, writes its config and a release workflow that runs only when started by hand, and optionally a check on release pull requests, listed in ciAllowlist.
disable-model-invocation: true
allowed-tools: Read Glob Grep Bash(git remote *) Bash(git log *) Bash(git status *) Bash(ls *)
---

# Enable releases

Say "Using enable-releases to ..." first. Releases follow SemVer, `0.x` during alpha, through release-please. Its workflow runs only when a person starts it: CI runs only for releases, never on every pull request. The templates are in `${CLAUDE_SKILL_DIR}/templates/`.

Nothing is written before the person says yes to the plan.

## 1. Preconditions

1. **A GitHub repo.** `git remote -v` must show an `origin` on github.com. If not, stop: release-please needs one.
2. **Conventional Commits.** release-please reads them to choose each version. Confirm them from `AGENTS.md`'s workflow rules, the `commit-msg` hook in `.githooks/`, or `git log --oneline -20`. If you can't, warn that release-please needs them, and recommend `/dev-workflow:setup` first.
3. **What's there already.** If `release-please-config.json`, `.release-please-manifest.json`, `.github/workflows/release-please.yml` or `.github/workflows/release-check.yml` exists, say what each holds. Stop and ask before overwriting any of them.
4. **Existing workflows.** One from an older setup may run release-please on every push. Existing workflows aren't changed unless the person asks: say what it does, recommend replacing it with the manual one, and ask.

## 2. Detect the release type

Look at the repo's root:

- `package.json` at the root: `node`
- `pyproject.toml` or `setup.py`: `python`
- `Cargo.toml`: `rust`
- `go.mod`: `go`
- `composer.json`: `php`
- none of them: `simple`

If more than one is there, ask which to use, recommending the one the project's releases are for.

## 3. Detect the first version

- `node`: `version` in `package.json`.
- `python`: `[project] version` in `pyproject.toml`, or `[tool.poetry] version`.
- `rust`: `version` under `[package]` in `Cargo.toml`.
- Anything else, or no version found: `0.1.0`.

## 4. Verify the versions

Never write an action's version from memory. Read the latest release of each, and use its current major version, such as `v5` for `v5.0.0`:

```sh
gh api repos/googleapis/release-please-action/releases/latest --jq .tag_name
gh api repos/actions/checkout/releases/latest --jq .tag_name
```

Read the release notes when the major version is newer than the templates' examples, and check the inputs the template uses still exist.

## 5. Ask

One question at a time, recommendation first:

1. **The default branch,** from `defaultBranch` in `.claude/dev-workflow.json`, or `gh repo view --json defaultBranchRef`. Confirm it only if neither gives one.
2. **The optional release check:** a workflow running the project's `check` command on release-please's pull requests, and no others. Recommend leaving it out: a release pull request changes only the changelog and versions, and pull requests opened with the default `GITHUB_TOKEN` don't start other workflows, so it would never run without a token of its own. Add it only with that token: a fine-grained token or a GitHub App's, saved as a repo secret such as `RELEASE_PLEASE_TOKEN`.

## 6. Show the plan, then write

List each file and what goes in it, then ask for a yes. After the yes, fill every placeholder in the templates, and leave none:

| Template | Written to | Placeholders |
|---|---|---|
| `release-please-config.json` | `release-please-config.json` | `<RELEASE_TYPE>` |
| `release-please-manifest.json` | `.release-please-manifest.json` | `<VERSION>` |
| `release-please.yml` | `.github/workflows/release-please.yml` | `<ACTION_MAJOR>`, `<DEFAULT_BRANCH>`, `<TOKEN_SECRET>`: `GITHUB_TOKEN`, or the token's secret with the check |
| `release-check.yml`, only with the check | `.github/workflows/release-check.yml` | `<DEFAULT_BRANCH>`, `<CHECKOUT_MAJOR>`, `<SETUP_STEPS>`, `<CHECK_COMMAND>` |

The release workflow has only `workflow_dispatch`. Never add a `push`, `pull_request` or `pull_request_target` trigger to it.

The release check has a `pull_request` trigger, so its job runs only on release-please's branches, with `if: startsWith(github.head_ref, 'release-please--')`, and it goes into `ciAllowlist`. Add it there before writing the file, or the hooks hold the file for a yes: rerun setup's write step with the whole list, the entries already there plus the new one, since a list in the answers replaces the one in the project file. `--plan` first, and `--apply` after the yes:

```sh
sh ${CLAUDE_PLUGIN_ROOT}/scripts/setup/run.sh --root . --plan --answers - <<'ANSWERS'
{ "ciAllowlist": [".github/workflows/release-check.yml"] }
ANSWERS
```

`<SETUP_STEPS>` and `<CHECK_COMMAND>` come from the project: `commands.check` in the project file, and the steps its stack file or the project's tooling needs to run it on a fresh machine, with each action's version verified as in step 4.

## 7. Report

1. The files written, the release type and the first version.
2. **GitHub settings:** in the repo's Settings, Actions, General, Workflow permissions, "Allow GitHub Actions to create and approve pull requests" must be on, or the action can't open its pull request. It's a change to the repo's settings, so leave it to the person.
3. **The token,** with the check: create it, save it as the secret the workflow names, and give it contents, pull requests and issues write access to this repo only.
4. **Releasing:** run the workflow by hand, from the Actions tab or `gh workflow run release-please.yml`, to open or update the release pull request. Merge that the methodology's way, squashed with a blank message, then run the workflow again to tag the release and publish it on GitHub.
5. **Next:** commit these files on a branch for their issue, such as `chore: enable release-please (#<issue>)`, and land it with `/dev-workflow:land`.
