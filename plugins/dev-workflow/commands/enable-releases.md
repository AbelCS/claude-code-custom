---
description: Enable Google's release-please in this project (must be a GitHub repo). Creates release-please-config.json, .release-please-manifest.json, and a GitHub Actions workflow.
allowed-tools: Read, Write, Edit, Bash, Glob
---

Set up [release-please](https://github.com/googleapis/release-please) for the current project so that conventional-commit-driven releases are automated via GitHub Actions.

## Preconditions

1. **Confirm GitHub repo.** Run `git remote -v`. If there is no `origin` pointing to `github.com`, stop and tell the user this command requires a GitHub-hosted repository.
2. **Confirm conventional commits in use.** Look for a CLAUDE.md rule, a commitlint config, or a recent `git log --oneline -20` showing conventional commit prefixes (`feat:`, `fix:`, etc.). If you cannot confirm, warn the user that release-please requires conventional commits to work — recommend installing `web-dev-workflow` first or running `/web-dev-workflow:setup`.
3. **Check for existing setup.** If `release-please-config.json`, `.release-please-manifest.json`, or `.github/workflows/release-please.yml` already exist, stop and ask the user before overwriting.

## Detect release-type

Inspect the repo to pick a `release-type`:

- `package.json` at root → `node`
- `pyproject.toml` or `setup.py` at root → `python`
- `Cargo.toml` at root → `rust`
- `go.mod` at root → `go`
- `composer.json` at root → `php`
- Otherwise → `simple`

If multiple are found, ask the user which to use.

## Detect initial version

- For `node`: read `version` from `package.json`.
- For `python`: read from `pyproject.toml` (`[project] version` or `[tool.poetry] version`).
- For `rust`: read `version` from `[package]` in `Cargo.toml`.
- Otherwise: default to `0.1.0`.

If no version is found, default to `0.1.0`.

## Write files

### 1. `release-please-config.json`

```json
{
  "$schema": "https://raw.githubusercontent.com/googleapis/release-please/main/schemas/config.json",
  "packages": {
    ".": {
      "release-type": "<DETECTED_RELEASE_TYPE>",
      "changelog-path": "CHANGELOG.md",
      "include-v-in-tag": true
    }
  },
  "bump-minor-pre-major": true,
  "bump-patch-for-minor-pre-major": true
}
```

### 2. `.release-please-manifest.json`

```json
{
  ".": "<DETECTED_VERSION>"
}
```

### 3. `.github/workflows/release-please.yml`

```yaml
name: release-please

on:
  push:
    branches:
      - main

permissions:
  contents: write
  pull-requests: write
  issues: write

jobs:
  release-please:
    runs-on: ubuntu-latest
    steps:
      - uses: googleapis/release-please-action@v4
        with:
          token: ${{ secrets.GITHUB_TOKEN }}
          config-file: release-please-config.json
          manifest-file: .release-please-manifest.json
```

If the project's default branch is not `main` (check with `git symbolic-ref refs/remotes/origin/HEAD` or `gh repo view --json defaultBranchRef`), substitute the actual default branch name in the `on.push.branches` list.

## Post-setup report

After writing the files, tell the user:

1. The three files that were created.
2. The detected release-type and initial version.
3. **Token note**: the workflow uses the default `GITHUB_TOKEN`, which works for most cases. If they need release-please's release PR to trigger other workflows (e.g. publish on tag), they must instead create a Personal Access Token, add it as a repo secret (e.g. `RELEASE_PLEASE_TOKEN`), and replace `secrets.GITHUB_TOKEN` with `secrets.RELEASE_PLEASE_TOKEN` in the workflow.
4. **Settings note**: in GitHub repo Settings → Actions → General → Workflow permissions, ensure "Allow GitHub Actions to create and approve pull requests" is enabled, otherwise the action cannot open the release PR.
5. Next step: commit the three new files with `chore: enable release-please`, push to the default branch, and release-please will open its first release PR on the next push.
