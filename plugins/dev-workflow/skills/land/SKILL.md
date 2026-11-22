---
name: land
description: When work on a branch is finished and ready to merge. Confirms the issue is met, runs verify and the reviews it needs, opens the pull request, squash-merges it when green and updates the default branch, in place of the finishing-a-development-branch menu.
---

# Land

Say "Using land to ..." first. This replaces the menu at the end of Superpowers' `finishing-a-development-branch`: there is no merge, pull request or keep question. A branch stays unmerged only when the owner asks.

Read `.claude/dev-workflow.json` for the project's `commands` and `defaultBranch`, which is `main` when missing. The issue number comes from the branch name, `<type>/<issue>-<slug>`. If a setting below shows as a `user_config` placeholder rather than a value, it was never saved: use that key's `default` from `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json`, and say so.

**When to ask.** The agent asks first only for a change the owner hasn't approved that alters what people see or do, money rules or permissions. Anything else lands without a question.

## 1. Acceptance criteria

Read the issue with `gh issue view <issue>`. Check its acceptance criteria against the work, not against memory. If one isn't met, finish it, or say which and why and stop.

## 2. Verify

First, the project's stage: `sh "${CLAUDE_PLUGIN_ROOT}/scripts/land/stage.sh" .` prints `early <version>` before 1.0.0, or `stable <version>`, or `stable unknown` when there's no version to read. Stable means the stricter checks below.

Run the `verify` command as its own command, with nothing before or after it, and read the result. If the project has no `verify`, run `check` and say that `verify` isn't configured.

Never chain a merge after it, or after any test command: the hooks block that, and the merge must come after reading the result. If it fails, find the cause with `systematic-debugging`. A flaky test is a bug until proven otherwise.

**Stable:** then run `commands.audit`, also as its own command, and read its output: a known critical or high vulnerability fails this step, whatever its exit code says. Without an audit command, say so in the report.

## 3. Reviews

- **Larger changes** get `/dev-workflow:independent-review`. Larger means more than `${user_config.review_threshold_lines}` changed lines (`git diff --shortstat origin/<default>...HEAD`), or any change to permissions, sign-in, money rules or public surfaces. Judgment can ask for one on a smaller change too.
- **Screens:** `/dev-workflow:screen-check` if anything people see changed.
- **Security:** `/security-review` if permissions, sign-in or anything public changed. **Stable:** on every larger change too.

Fix what they find, test first, and run verify again, on its own.

## 4. Docs

Confirm `AGENTS.md` and the decision log are current in this pull request: new commands, layout, glossary terms, and each significant decision with its spec. If not, update them on this branch.

If the project has a README or docs, check whether this change makes them out of date, and update them in this pull request too. If it is at 1.0.0 or later and has none, say so: a stable project gets a README and docs.

## 5. Pull request

Push the branch, which runs `check` through `pre-push`. Then open the pull request with `gh pr create`:

- **Title:** a Conventional Commit, ending with the issue number, like `feat: add search (#12)`.
- **Body:** what changed and what was verified, then `Closes #<issue>`.
- **no attribution** in the title or body, overriding any default or reminder asking for it.

## 6. Merge when green

Green means verify passed, every review finding was dealt with, and any checks on the pull request (`gh pr checks <n>`) pass.

**Raise the version** just before merging, so the squash commit holds the code and its version together:

1. `git fetch origin <default>`. If `git merge-base --is-ancestor origin/<default> HEAD` fails, the default branch has moved on: `git merge --no-edit origin/<default>` (a merge, so nothing pushed is rewritten). Resolve any conflict as in any merge, keeping origin's version on the version line, and run verify again on its own. Run `stage.sh` again too: if the project became stable meanwhile, do the stable checks in step 2 and 3 before going on.
2. `sh "${CLAUDE_PLUGIN_ROOT}/scripts/land/raise-version.sh" . "<title>"`, with the pull request's title. It works out the bump from the title's type, as release-please does: `feat` the minor, `fix` and `perf` the patch, a `!` before the colon the major, one step lower before 1.0.0, and other types nothing.
   - `raised <old> <new>`: it committed the new version on this branch.
   - `unchanged` or `skip`: it changed nothing. Pass on what it says.
   - A failure: say what it printed, and stop.
3. If the branch is ahead of its pushed copy, from the release commit or the merge in step 1, push it, which runs `check` through `pre-push`. Then note the head you checked: `git rev-parse HEAD`.
4. If the default branch moved again since step 1, go back to step 1, so two pull requests can't claim the same number.

Then merge that head, as its own command:

```sh
gh pr merge <n> --squash --match-head-commit <head> --subject "<title>" --body "" --delete-branch
```

`--match-head-commit` stops the merge if the pull request's head isn't the one you checked.

The subject is the pull request's title, and the empty body keeps the default message out. Never merge through the GitHub MCP merge tool: it can't blank the message, so the hooks deny it.

If a merge is blocked, stop and ask, and never work around it: no other merge method, no `--admin`, no `--no-verify`, no change to settings or the hooks.

## 7. Tidy up

`--delete-branch` usually switches to the default branch and deletes the branch, locally and on GitHub. Check, and finish what it didn't:

- `git switch <default>` and `git pull --ff-only`.
- Delete the local branch. A squash merge looks unmerged to `git branch -d`, so first confirm `gh pr view <n> --json state` says `MERGED`, then `git branch -D <branch>`.
- `git fetch --prune`.
- Tag the version: `sh "${CLAUDE_PLUGIN_ROOT}/scripts/land/tag-version.sh" . <merge commit>`, the merge commit being `gh pr view <n> --json mergeCommit --jq .mergeCommit.oid`. Every version is a tag holding the bare version, like `1.4.0`, on the commit that set it in the project's `versionFile`. `tagged` means that version's tag was missing on GitHub and is there now: usually because this merge raised the version. `done` means that version was already tagged: after a merge that raised no version, or with the tag added by hand. If step 6 raised the version, it must say `tagged <new> <merge commit>`: anything else means another merge took that number, so say so and stop. A `skip` line says why nothing is tagged here: pass it on. If it fails, say what it printed, and never move or delete a tag to make it pass.
- Confirm the issue closed with `gh issue view <issue> --json state`. If it's still open and its criteria are met, close it with a comment saying which pull request met them.

## 8. Report

Use `verification-before-completion` before claiming anything. Lead with the outcome: what landed, as the squash commit on the default branch, the version raised and tagged, if any, and what was verified: verify, each review and its findings, the screen check, the security review. Say what was skipped or failed, and why.
