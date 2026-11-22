---
name: readiness
description: When the owner asks to release 1.0.0, go stable, go live or deliver. Runs the readiness review a project passes before its first stable version, security first, turns findings into issues, and records the result in docs/readiness.md, which land's gate needs before raising to 1.0.0.
---

# Readiness

Say "Using readiness to ..." first. Before 1.0.0 a project can favour speed. Its first stable version is the one people rely on, so it passes this review first. `land` won't raise the version from below 1.0.0 to 1.0.0 or above without its entry in `docs/readiness.md`: `scripts/land/raise-version.sh` checks, and so does `${CLAUDE_PLUGIN_ROOT}/scripts/readiness/check-entry.sh`.

Read `.claude/dev-workflow.json` for `commands`, `hasScreens` and `versionFile`, and `AGENTS.md` for what the project is. Work on a branch for the review's own issue, like `chore/<issue>-readiness`.

## 1. The version

Confirm the version this is for with the owner, recommending `1.0.0`, or the next major if the project is already a 0.x with breaking changes behind it. A release candidate such as `1.0.0-rc.1` doesn't need this review; the step from it to `1.0.0` does.

## 2. The checklist

Go through each item. Each ends as one of:

- **done:** it was checked, and it holds;
- **not applicable:** it doesn't fit this project, such as monitoring for a library, with why;
- **accepted:** the owner knowingly goes live without it, with why, in their words. Only the owner accepts: ask, one question at a time, recommendation first.

A finding that needs work becomes a GitHub issue, with objective, scope and acceptance criteria, and the item stays open until that issue is closed or the owner accepts it. Fixes land the usual way, through `land`.

| Item | What it takes |
|---|---|
| **Security review** | `/security-review` over the whole codebase, not just a branch's changes, then `/dev-workflow:independent-review` with a security brief: the files that handle sign-in, permissions, money, personal data, uploads and anything public, by path. Check every finding against the code |
| **Dependencies** | `commands.audit`, read in full. No known critical or high vulnerability left open. Without an audit command, say so: it's a gap to fill, in `.claude/dev-workflow.json` and the project's tooling |
| **Secrets in the history** | A real secret scanner over the whole history, such as gitleaks, using its current command from its own help. A secret found was exposed: it's revoked and replaced, not just deleted. With no scanner installed, give its install command; the item stays open until one runs or the owner accepts it |
| **Permissions** | Every route and data access checks who may do it, on the server, with tests: `/dev-workflow:conventions-code`'s rules. Where the database has row-level rules, every table has them and they're tested |
| **README and docs** | Current with the code, and say how to install, run and operate it |
| **Data** | If it keeps data: backups exist, a restore was tried and worked, personal data has a retention rule and a way to delete it |
| **Monitoring** | If it runs as a service: errors are tracked, there's a health check, and logs hold no secrets or personal data |
| **Accessibility** | If it has screens: every main flow passes `/dev-workflow:screen-check` |
| **Performance** | If people wait on it: a budget for the main pages or endpoints, measured, and met |
| **Releases** | Whether people relying on it need release notes: `/dev-workflow:enable-releases` if so. If it's set up, its config is checked for this version too |

## 3. The entry

Only when every item is done, not applicable or accepted, add the entry to `docs/readiness.md`, creating the file with a `# Readiness` heading if it's missing. The entry's heading is exactly `## <version>, <YYYY-MM-DD>`, with today's date from `date +%Y-%m-%d`, then a table:

```markdown
## 1.0.0, 2026-11-22

| Item | Outcome | Why |
|---|---|---|
| Security review | Done | Two findings, fixed in #41 and #42 |
| Monitoring | Not applicable | A library: nothing runs as a service |
| Performance | Accepted | The owner goes live without a budget for the admin pages, which few people use |
```

Then confirm `land`'s gate will read it:

```sh
sh "${CLAUDE_PLUGIN_ROOT}/scripts/readiness/check-entry.sh" . <version>
```

Then the version:

- **Without release-please:** commit the entry with the version's raise, `chore: release <version> (#<issue>)`, changing `versionFile` by hand to the version, and land it with `/dev-workflow:land`. Its raise step finds the version raised and the entry in place.
- **With release-please:** land the entry on its own, `docs: readiness for <version> (#<issue>)`. release-please raises the version in its own release pull request: set `release-as` to the version in its config if it wouldn't choose it, and `land` checks the entry is there before that pull request merges.

## 4. Report

Lead with the outcome: ready, or what's still open. Then each item's outcome, the issues opened, and what the owner accepted. From this version on, `land` applies the stable rules: a security review of every larger pull request, and the dependency audit after `verify`.
