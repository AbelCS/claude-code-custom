# The readiness gate: security that grows with the version

Issue: [#35](https://github.com/AbelCS/claude-code-custom/issues/35). Status: approved by the owner on 2026-11-22. Builds on [raising the version](2026-11-21-raise-version-design.md).

## Problem

The methodology asks for `/security-review` when permissions, sign-in or anything public changes. Nothing else about security, or any other non-functional work, depends on where a project is. A prototype and an app with real users get the same checks.

That is wrong in both directions. A prototype doesn't need a dependency audit on every merge. A project about to go live does need someone to look at backups, monitoring and the whole app's security, and nothing asks for it. And one thing can't wait for any stage: a secret committed on day one stays in the history for good.

## Decisions

The owner's:

1. **Security and other non-functional work scale with maturity, and maturity is the version.** Not a manual switch: a switch gets forgotten, and some security can't wait for one.
2. **Three stages.** Basics that are always on. A readiness gate at 1.0.0. Stricter checks from 1.0.0 on.
3. **Reaching 1.0.0 is the gate.** `land` never raises to 1.0.0 by itself: before 1.0.0 a breaking change raises the minor. So 1.0.0 is always a deliberate step by a person, which makes it the natural place to stop and check.

The details, chosen as defaults:

4. **The always-on basic is a secrets check in `pre-commit`.** It is the one thing that can't be fixed later, and a git hook sees every commit, by a person or an agent. `/security-review` on changes to permissions, sign-in or anything public stays as it is.
5. **High-confidence patterns only.** A check that cries wolf gets skipped or allowlisted wholesale. It isn't a full scanner, and doesn't claim to be.
6. **It names the file and the kind of secret, never the value.** Hook output ends up in terminals, logs and transcripts.
7. **A project allows paths, not patterns,** through `secretsAllowlist` in the project file. A fixture that holds a fake key is a fact about a file. Switching a pattern off would hide real keys everywhere.
8. **The gate is a skill for the judgment and a script for the rule.** `/dev-workflow:readiness` does the review. `raise-version.sh` refuses 1.0.0 without its entry. Neither is enough alone: a skill can be skipped, and a script can't review an app.
9. **Each checklist item ends as done, not applicable or accepted, with a reason.** An honest "accepted: no backups yet, one user, data is re-importable" is better than a checklist nobody can pass. Findings become issues, closed or accepted before the entry is written.
10. **A first version file isn't gated.** A project adopting the plugin at 2.3.0 isn't asked to go back. Raises within 1.x and below 1.0.0 are unaffected.
11. **From 1.0.0 on, `land` reads the stage from the version on origin's default branch:** every larger pull request also gets `/security-review`, and the dependency audit runs after `verify`, with a known critical vulnerability as a failure.
12. **Stricter when unknown.** A project without a `versionFile` can't show its stage, so `land` applies the stable rules.
13. **The rules say all this by stage,** in the managed `AGENTS.md` sections.
14. **This repo follows it.** It is past 1.0.0, so the stable rules apply from now on. It isn't asked for a retroactive readiness entry. The plugin goes to 1.4.0 through `land`'s own raise.

## Design

### Secrets in `pre-commit`

A new check in the hook template, run first, before workflows and formatting. POSIX `sh` with `git` and `grep`, like every git hook: no `jq`, Node or Python. For each staged file that isn't deleted:

- **By name,** the last part of the path: `.env` and `.env.*`, except `.env.example`, `.env.sample` and `.env.template`. And `*.pem`, `*.key`, `*.p12`, `*.pfx`, `id_rsa` and `id_ed25519`.
- **By content,** the staged added lines only (`git diff --cached -U0`, lines starting with `+`). Removing a secret is what should happen, so removed lines aren't read. The kinds: a private key block (`-----BEGIN ... PRIVATE KEY-----`), an AWS access key ID, a GitHub token, a Slack token, a Stripe live key, a Google API key, an Anthropic key and an OpenAI project key. Each pattern needs the prefix and a body of the real length, so a prefix alone in prose passes.

A match blocks the commit with the file, the kind, and what to do: take it out and revoke it if it was ever shared, or allow the path. The patterns sit in the hook itself, one per line as `<kind>|<pattern>`.

**The allowlist.** `secretsAllowlist` in `.claude/dev-workflow.json` is a list of globs, read as shell `case` patterns like the formatter globs, where `*` also matches `/`. Setup writes them to `.githooks/dev-workflow.env` as `DW_SECRETS_ALLOW`, one per line. The hook unsets the variable before loading the file, so a caller's environment can't allow anything. A file from an older plugin has no such line: that reads as an empty list, not a broken file, so an upgrade never locks commits. With no env file at all the check still runs, with an empty list.

### `/dev-workflow:readiness`

A new skill, model-invocable. Its description starts with the trigger: the owner asks for 1.0.0, or to go stable or live. It works on a branch, with an issue, like any task. The checklist:

| Item | Applies | What it does |
|---|---|---|
| Security review | always | `/security-review` briefed on the whole codebase, plus `/dev-workflow:independent-review` with a security brief naming the entry points |
| Dependency audit | always | runs `commands.audit` |
| Secrets in the history | always | a real scanner over every commit, such as gitleaks, when installed |
| README and docs | always | they exist and match the code |
| Releases | always | considered: `/dev-workflow:enable-releases`, or a reason not to |
| Data | has a database | backups exist, a restore was tested, personal data has a retention rule |
| Monitoring | runs as a service | error tracking, a health check, logs without personal data |
| Accessibility | has screens | every main flow, through `/dev-workflow:screen-check` |
| Performance | has pages or endpoints | a budget for the main ones, measured |

Each item ends as **done**, **not applicable** or **accepted**, each with a reason. Accepting a risk is the owner's call, asked one question at a time. A finding becomes an issue. Every such issue is closed or accepted before the entry is written. A missing tool, such as no `audit` command or no scanner, is said plainly: the item stays open until it runs or the owner accepts it.

**The entry** goes to `docs/readiness.md`, created if missing, as a section headed exactly `## <version>, <YYYY-MM-DD>`, with a table of items, outcomes and reasons. Only a complete review writes the heading. A script writes it, `scripts/readiness/write-entry.sh`, and the heading's format lives in one library, `scripts/lib/readiness.sh`, which the gate reads too. So the writer and the gate can't disagree.

Then the skill sets the version in `versionFile` to 1.0.0 by hand, on the same branch, and lands it. `raise-version.sh` sees a version already raised, checks the gate, and leaves it. `tag-version.sh` tags it after the merge.

### The gate in `raise-version.sh`

One new check, after both versions are read and before `skip already-raised`, since 1.0.0 always arrives raised by hand. When the branch's version is 1.0.0 or above, and origin's is below 1.0.0, the script looks in `docs/readiness.md`, as committed on the branch, for a heading for that exact version. Without one it exits 1, names the version, and says to run `/dev-workflow:readiness`. With one it carries on as before.

- **Order is SemVer's.** `1.0.0-rc.1` is below 1.0.0, so a release candidate isn't gated, and `1.0.0-rc.1` to `1.0.0` is.
- **Any jump is covered:** 0.9.2 to 2.0.0 needs an entry for 2.0.0.
- **`skip first-version` stays above it,** so a first version file passes.
- **With release-please and a `versionFile`,** the check runs before `skip release-please`, so a release pull request that reaches 1.0.0 is gated too. The entry lands first, in an ordinary pull request.

### `land`

- **Stage.** A new script, `scripts/land/stage.sh <root>`, prints `early <version>` or `stable <version>` from the `versionFile` on origin's default branch, or the branch's copy when origin has none yet. With no `versionFile` it prints `stable unknown`. `land` runs it before the reviews.
- **Reviews.** When stable, every larger pull request gets `/security-review` as well as the independent review. When early, the security review stays tied to permissions, sign-in and anything public.
- **Audit.** When stable, after `verify`, `land` runs `commands.audit` as its own command and reads the output. A known critical vulnerability stops the landing. Lower ones are reported. No `audit` command: it says so.
- **The gate.** A refusal from `raise-version.sh` stops the landing, as any failure does. `land` passes on the message, and never writes a readiness entry to get past it.

The pull request that reaches 1.0.0 is still early: the readiness review covers it.

### The rules and the docs

The templates in `skills/setup/templates/agents/` say it by stage: `testing.md` that `pre-commit` refuses a staged secret, `tools.md` when `/security-review` runs before and from 1.0.0 and that `/dev-workflow:readiness` comes before 1.0.0, `workflow.md` that 1.0.0 needs a readiness entry. The README, the workflow guide, `enable-releases` and the project file's schema follow.

### This repo

Its hooks and managed sections are the plugin's own, so they change in the same pull request. `AGENTS.md` says the stable rules apply here, with no `audit` command, since the repo has no dependencies. The tests for the secrets check build each fake secret from pieces at run time, so no file here holds one whole.

## Out of scope

- A full secret scanner in the hook: entropy checks, hundreds of providers, scanning binary files.
- Compliance frameworks, such as SOC 2 and ISO 27001.
- Per-environment deployment checks.
- A second gate at later major versions.

## Known limits

- **The hook's patterns miss custom secrets:** a password in a config file, an internal token with no known shape, a secret in a binary file. The history scan at the gate catches more, once.
- **The gate trusts the entry.** It checks that a heading exists, not that the review was honest or complete. A person can write the heading by hand.
- **`--no-verify` skips the hook,** as it skips every hook. The rules forbid it, and the Claude Code hooks block it for the agent.
- **release-please without a `versionFile`** has no version the script can read, so nothing gates it mechanically. `enable-releases` says to run the readiness skill before a release that reaches 1.0.0.
- **The audit's exit code isn't the rule.** Stack files set their own level, so `land` reads the output for critical findings. That is judgment, not a script.
