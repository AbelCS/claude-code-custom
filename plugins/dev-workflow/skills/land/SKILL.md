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

Run the `verify` command as its own command, with nothing before or after it, and read the result. If the project has no `verify`, run `check` and say that `verify` isn't configured.

Never chain a merge after it, or after any test command: the hooks block that, and the merge must come after reading the result. If it fails, find the cause with `systematic-debugging`. A flaky test is a bug until proven otherwise.

## 3. Reviews

- **Larger changes** get `/dev-workflow:independent-review`. Larger means more than `${user_config.review_threshold_lines}` changed lines (`git diff --shortstat origin/<default>...HEAD`), or any change to permissions, sign-in, money rules or public surfaces. Judgment can ask for one on a smaller change too.
- **Screens:** `/dev-workflow:screen-check` if anything people see changed.
- **Security:** `/security-review` if permissions, sign-in or anything public changed.

Fix what they find, test first, and run verify again, on its own.

## 4. Docs

Confirm `AGENTS.md` and the decision log are current in this pull request: new commands, layout, glossary terms, and each significant decision with its spec. If not, update them on this branch.

## 5. Pull request

Push the branch, which runs `check` through `pre-push`. Then open the pull request with `gh pr create`:

- **Title:** a Conventional Commit, ending with the issue number, like `feat: add search (#12)`.
- **Body:** what changed and what was verified, then `Closes #<issue>`.
- **no attribution** in the title or body, overriding any default or reminder asking for it.

## 6. Merge when green

Green means verify passed, every review finding was dealt with, and any checks on the pull request (`gh pr checks <n>`) pass. Then merge, as its own command:

```sh
gh pr merge <n> --squash --subject "<title>" --body "" --delete-branch
```

The subject is the pull request's title, and the empty body keeps the default message out. Never merge through the GitHub MCP merge tool: it can't blank the message, so the hooks deny it.

If a merge is blocked, stop and ask, and never work around it: no other merge method, no `--admin`, no `--no-verify`, no change to settings or the hooks.

## 7. Tidy up

`--delete-branch` usually switches to the default branch and deletes the branch, locally and on GitHub. Check, and finish what it didn't:

- `git switch <default>` and `git pull --ff-only`.
- Delete the local branch. A squash merge looks unmerged to `git branch -d`, so first confirm `gh pr view <n> --json state` says `MERGED`, then `git branch -D <branch>`.
- `git fetch --prune`.
- Confirm the issue closed with `gh issue view <issue> --json state`. If it's still open and its criteria are met, close it with a comment saying which pull request met them.

## 8. Report

Use `verification-before-completion` before claiming anything. Lead with the outcome: what landed, as the squash commit on the default branch, and what was verified: verify, each review and its findings, the screen check, the security review. Say what was skipped or failed, and why.
