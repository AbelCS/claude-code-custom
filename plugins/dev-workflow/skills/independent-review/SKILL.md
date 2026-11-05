---
name: independent-review
description: Before merging a larger pull request, or when someone asks for an outside review by another model. Announces the reviewer, runs the reviewer command with a narrow brief naming the files, and checks each finding against the code before acting on it.
---

# Independent review

Say "Using independent-review to ..." first. `land` calls this for a larger pull request: one with more than `${user_config.review_threshold_lines}` changed lines, or any change to permissions, sign-in, money rules or public surfaces.

The settings below come from the plugin's `/config`. If one shows as a `user_config` placeholder rather than a value, it was never saved: use that key's `default` from `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json`, and say so.

## 1. Write the brief

A narrow brief gets a useful review. It says:

- what changed and why, from the issue;
- the files to read, by path, naming the files rather than "the repo": `git diff --name-only origin/<default>...HEAD` lists them;
- what to look for: correctness bugs, broken rules from `AGENTS.md`, missing or weak tests, and security where permissions, sign-in or anything public changed;
- what's out of scope;
- that the review is read-only, and each finding should give its file, line, severity and why.

Never put secrets or private terms in it. The brief goes inside the command's quotes, so leave out double quotes, backticks, `$` and backslashes, or escape them.

## 2. Announce, then call

Announce `${user_config.reviewer_name}` before calling it, naming the files: "Asking ${user_config.reviewer_name} to review ...".

Then run `${user_config.reviewer_command}` with `<brief>` replaced by the brief. Run it as its own command, with a long timeout: a review can take several minutes.

## 3. If it fails

If Codex is missing, the command's first word isn't found, it exits non-zero, or it prints an error instead of a review, say so plainly with the error. Then ask whether to go ahead without it. Never skip it silently, never call a failed review a pass, and never use another model in its place without asking and naming that model.

## 4. Check each finding

Use `receiving-code-review`: check each finding against the code before acting on it. Each one is:

- **valid:** fix it, test first;
- **not valid:** say why, pointing at the code;
- **the owner's call:** a product decision, or a change to what people see or do, money rules or permissions. Ask, one question at a time.

Don't agree for the sake of it, and don't fix what you haven't confirmed.

## 5. Report

Say what it was asked: the files and the brief, briefly. Then what it found, attributed to ${user_config.reviewer_name}, and for each finding whether it was fixed, rejected and why, or left for the owner. After fixes, `verify` runs again before any merge.
