# Readiness gate Implementation Plan

**Goal:** `pre-commit` refuses a staged secret from the first commit. Reaching 1.0.0 needs a readiness entry, written by a new skill and checked by `raise-version.sh`. From 1.0.0 on, `land` adds a security review to every larger pull request and runs the dependency audit.

**Spec:** `docs/superpowers/specs/2026-11-22-readiness-gate-design.md`. Read it first, and the raise-version spec it builds on.

**Delivery:** One issue, [#35](https://github.com/AbelCS/claude-code-custom/issues/35), one branch, `feat/35-readiness-gate`, one squash-merged pull request. Each commit subject ends with `(#35)`.

## Constraints

- Test first, in every step. Run the one test file, then `scripts/check` before moving on.
- Git hooks are POSIX `sh` with no `jq`, Node or Python. Plugin scripts may need `jq`.
- No file in this repo holds a whole secret-shaped string, fake or not: this repo's own hook would refuse it. Tests build each one from pieces at run time.
- Each test uses its own temp repo, with a bare remote where it needs an origin, as `tests/land/raise-version.test.sh` does.
- Wording about a framework, a database or a named service stays in `plugins/dev-workflow/stacks/`. The skill says "error tracking", not a product. Model names stay out of skills.
- No AI attribution. Nothing private named.

Paths below are under `plugins/dev-workflow/` unless they start with `tests/`, `docs/`, `.claude/`, `.githooks/` or name a root file.

## Steps

- [ ] **1. `pre-commit`: the secrets check.**
  Files: `skills/setup/templates/githooks/pre-commit`, `tests/githooks/secrets.test.sh` (new).
  Tests, by real commits in a temp repo: each content kind is refused, naming the file and the kind, and the output never holds the value. Each file kind is refused, in a subfolder too. `.env.example`, `.env.sample` and `.env.template` pass. Ordinary code passes, and so does a prefix alone in prose. A removed secret line and a deleted secret file pass. A path with a space works. `tests/githooks/pre-commit.test.sh` passes unchanged.

- [ ] **2. The allowlist, from the project file to the hook.**
  Files: `skills/setup/references/project-file.schema.json` (`secretsAllowlist`: strings with no line break and no braces), `scripts/setup/project-file.sh` (the answers it merges, and `DW_SECRETS_ALLOW` in the env it writes), `skills/setup/references/answers.md`, `skills/setup/SKILL.md` where it lists the fields.
  Tests: `tests/setup/project-file.test.sh` (the field is accepted, a bad glob refused, the env line written, empty when the field is missing), `tests/setup/install-hooks.test.sh` if it holds an expected env. In `secrets.test.sh`: an allowed path passes by name and by content, a glob covers a folder, `DW_SECRETS_ALLOW` from the caller's environment is ignored, an env file without the line reads as an empty list, and no env file still scans.

- [ ] **3. `scripts/lib/readiness.sh` and `scripts/readiness/check-entry.sh`.**
  Files: both new, `tests/land/readiness-entry.test.sh` (new).
  The library says whether content on stdin has the heading for a version, and whether a version is before 1.0.0 or stable, in SemVer's order. The skill writes the entry itself, then runs the check, which reads it through the library, as the gate does.
  Tests: the entry for a version is found; another version's, a heading without a date or with text after it, a candidate's, and a version with other characters for the dots are not; a version that isn't bare SemVer is refused.

- [ ] **4. `raise-version.sh`: the gate.**
  Files: `scripts/land/raise-version.sh` (sources `lib/readiness.sh`; the check sits after `old` is read and before `skip already-raised`; the header comment), `tests/land/raise-version.test.sh`.
  Tests: 0.9.2 on origin and 1.0.0 on the branch is refused, exit 1, nothing changed, naming the version and the skill. With an entry for 1.0.0 it prints `skip already-raised`. An entry for another version is refused. An entry only in the work tree, uncommitted, doesn't count. 0.9.2 to 2.0.0 needs the entry for 2.0.0. `1.0.0-rc.1` from 0.9.2 isn't gated, and 1.0.0 from `1.0.0-rc.1` is. A first version file at 2.3.0 still prints `skip first-version`. 1.2.1 with `feat` still gives 1.3.0, and 0.4.2 with `feat!` still gives 0.5.0, with no `docs/readiness.md`. With `release-please-config.json` and a `versionFile`: gated the same, then `skip release-please`. Without a `versionFile`: the skip as today. One round trip: an entry from `write-entry.sh` passes the gate.

- [ ] **5. `scripts/land/stage.sh`.**
  Files: new, with `tests/land/stage.test.sh` (new).
  Tests: 0.4.2 prints `early 0.4.2`, 1.0.0 and 1.3.0 `stable`, `1.0.0-rc.1` `early`. No `versionFile` prints `stable unknown`. A version file on the branch but not yet on origin is read from the branch. The version comes from origin, not the branch, when both have one. A version that isn't SemVer exits 1. No project file exits 2.

- [ ] **6. The readiness skill.**
  Files: `skills/readiness/SKILL.md` (new, under 500 lines, the description starting with the trigger), `evals/readiness-fires/` and `evals/readiness-quiet/` (new, shaped like `land-fires` and `land-quiet`), `skills/independent-review/SKILL.md` (a caller may hand it a brief, here a security one naming entry points, not a diff).
  The skill: the checklist, which items apply from `hasScreens` and `stack`, the three outcomes with reasons, findings to issues with `gh issue create`, the owner asked before anything is accepted, the entry through `write-entry.sh` only when every item has an outcome and every finding's issue is closed or accepted, then the version set by hand and `/dev-workflow:land`.
  Tests: `tests/skills/content.test.sh` pins the script's name, the three outcomes, `docs/readiness.md`, `/security-review`, `commands.audit` and `enable-releases`. `tests/skills/stack-words.test.sh` passes.

- [ ] **7. `land` by stage.**
  Files: `skills/land/SKILL.md`: `stage.sh` before the reviews, `/security-review` for every larger change when stable, the audit after verify when stable with critical as a failure, and the gate's refusal in step 6. `skills/enable-releases/SKILL.md`: the readiness skill before a release that reaches 1.0.0.
  Tests: `tests/skills/content.test.sh` pins `stage.sh`, `commands.audit`, "critical" and the stable-when-unknown wording. The `land-fires` and `land-quiet` evals are unchanged.

- [ ] **8. The rules.**
  Files: `skills/setup/templates/agents/testing.md` (the hooks line), `tools.md` (the `/security-review` line by stage, and a line for `/dev-workflow:readiness`), `workflow.md` (1.0.0 needs a readiness entry).
  Tests: `tests/setup/agents-md.test.sh` and `tests/setup/template.test.sh`, with any expected text they hold. Check that a project with the old, unedited sections gets the new ones on a rerun.

- [ ] **9. This repo.**
  `tests/repo.test.sh` wants setup's plan here to be all `keep`, and `.githooks/` to match the templates, so this repo is upgraded in the same pull request, by this branch's own setup scripts, not by hand: the managed sections of `AGENTS.md`, `.githooks/pre-commit`, `.githooks/dev-workflow.env` and the hashes in `.claude/dev-workflow.json`.
  Files: those, `tests/repo.test.sh` (the expected env gains `DW_SECRETS_ALLOW=''`), and `AGENTS.md` by hand outside the managed sections: the Layout row for `docs/readiness.md` is not needed here, but "In this repo" says the stable rules apply, with no `audit` command and no retroactive entry, and its line about rules reaching this file after the release is corrected.
  Then make one commit through the new hook, to see it pass on this repo's own files.

- [ ] **10. The docs.**
  Files: `README.md` (the skills table, which `tests/readme.test.sh` checks against the folders, the `secretsAllowlist` setting, the hooks section, upgrade notes for 1.4.0), `docs/workflow-guide.md` (the stages, the landing steps, the "A project reaching 1.0.0" row, the glossary), `docs/hook-behaviour.md` if it lists what `pre-commit` does. `docs/decisions.md` is done with the spec.
  Tests: `tests/readme.test.sh`. Then `scripts/check`.

- [ ] **11. Landing.**
  Leave `plugin.json` at 1.3.0: `land` raises it. Run the skill evals for the two new cases, about a dollar, and say what they cost.
  Then land from this branch's own copy of the scripts: `scripts/verify` as its own command, the independent review, and `/security-review`, since this repo is stable. `stage.sh` prints `stable 1.3.0`. There is no `audit` command, and `land` says so. The pull request is titled `feat: always-on security basics, and a readiness gate before 1.0.0 (#35)`. `raise-version.sh` prints `raised 1.3.0 1.4.0`, with no gate, and commits `chore: release 1.4.0 (#35)`. Push, merge. `tag-version.sh` prints `tagged 1.4.0`. Set `pluginVersion` wherever setup's rerun puts it, and tick the issue's criteria.
