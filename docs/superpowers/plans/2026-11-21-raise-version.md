# Raise version Implementation Plan

**Goal:** Without release-please, `land` raises the version before every merge whose pull request title calls for it, from the version on origin's default branch. With release-please, nothing changes.

**Spec:** `docs/superpowers/specs/2026-11-21-raise-version-design.md`. Read it first, and the version-tags spec it builds on.

**Delivery:** One issue, [#31](https://github.com/AbelCS/claude-code-custom/issues/31), one branch, `feat/31-raise-version`, one squash-merged pull request. Each commit subject ends with `(#31)`.

## Constraints

- Test first, in every step. Run the one test file, then `scripts/check` before moving on.
- Scripts are POSIX `sh`. The new ones may need `jq`, as `tag-version.sh` does. No Node or Python.
- Each test uses its own temp repo with a bare remote, as `tests/land/tag-version.test.sh` does.
- Wording about a framework stays in `plugins/dev-workflow/stacks/`. File names such as `package-lock.json` are not framework wording.
- No AI attribution. Nothing private named.

Paths below are under `plugins/dev-workflow/` unless they start with `tests/`, `docs/`, `.claude/` or name a root file.

## Steps

- [ ] **1. `scripts/lib/version-file.sh`: reading, moved out of `tag-version.sh`.**
  Files: `scripts/lib/version-file.sh` (new), `scripts/land/tag-version.sh` (sources it, drops its own reader and SemVer pattern), `tests/lib-version-file.test.sh` (new, or under `tests/land/`, wherever the other `lib` tests sit).
  Tests: the reader on `.json`, `.toml` (each of the four tables, and a `version` in another table not read) and a plain file. The SemVer check accepts `1.4.0` and `2.0.0-rc.1`, refuses `v1.2.0` and `1.2`. `tests/land/tag-version.test.sh` passes unchanged: that is the proof the move changed nothing.

- [ ] **2. `version-file.sh`: writing.**
  Files: `scripts/lib/version-file.sh`, the same test file.
  Tests: one case each for `.json`, `.toml` and a plain file, comparing the file before and after: only the version text differs. Cover tabs and four-space indentation, a file with no last newline, CRLF line endings, and a `.toml` with a dependency's `version` before and after the real one. A JSON file whose first `"version"` isn't the top-level one is refused and left byte for byte as it was. A file that doesn't hold the old version is refused.

- [ ] **3. `scripts/land/raise-version.sh`: the bump.**
  Files: `scripts/land/raise-version.sh` (new), `tests/land/raise-version.test.sh` (new).
  Tests, each with a branch `feat/7-x` off a default branch pushed to a bare origin. From 1.2.1: `feat` gives 1.3.0, `fix` and `perf` 1.2.2, `feat!` and `fix!` 2.0.0, a scope with and without `!`. From 0.4.2: `feat!` gives 0.5.0, `feat` 0.4.3, `fix` 0.4.3. Each prints `raised <old> <new>` and makes one commit, `chore: release <new> (#7)`, changing one line of the version file and leaving the work tree clean. A branch with no issue number gets the subject without one. Each of `docs`, `chore`, `test`, `refactor`, `ci`, `build`, `style` and `revert` prints `unchanged`, with no commit.

- [ ] **4. `raise-version.sh`: what it skips and refuses.**
  Files: the same two.
  Tests: `2.0.0-rc.1` prints `skip pre-release`. A version already raised on the branch prints `skip already-raised`. `release-please-config.json` and no `versionFile` each print their skip. All exit 0 with no commit. Refused, exit 1, nothing changed: a title that isn't a Conventional Commit, a version on origin that isn't SemVer, uncommitted changes, the default branch itself checked out, and a default branch that moved on origin, which passes once it's merged in and then raises from the new number. Usage errors exit 2.

- [ ] **5. `land` raises before the merge.**
  Files: `skills/land/SKILL.md`: a new step between the pull request and the merge (run the script, merge the default branch in and verify again if it says the branch is behind, push the release commit), the later steps renumbered, the tag step's wording (`tagged` is now the usual result after a `feat` or `fix`), and the report. Keep it under 500 lines.
  Tests: `tests/skills/content.test.sh` pins the script's name, `git merge origin/` and that verify runs again after it. The `land-fires` and `land-quiet` evals are unchanged.

- [ ] **6. The rules.**
  Files: `skills/setup/templates/agents/workflow.md` (the versions line), `AGENTS.md` (the same line in Workflow), `skills/enable-releases/SKILL.md` if it says who raises the version without release-please.
  Tests: `tests/setup/agents-md.test.sh` and `tests/repo.test.sh`, with any expected text they hold. Check that a project with the old, unedited section gets the new one on a rerun.

- [ ] **7. The docs.**
  Files: `README.md` (the workflow's finish step, the `land` row, upgrade notes for 1.3.0), `docs/workflow-guide.md` (the landing steps, "The version tag", "Versions and releases", the glossary's Tag row), `docs/hook-behaviour.md` only if it describes landing. `docs/decisions.md` is done with the spec.
  Tests: `tests/readme.test.sh`. Then `scripts/check`.

- [ ] **8. This repo, and landing.**
  Files: `tests/marketplace.test.sh` (the version is bare SemVer, not a pinned `1.2.1`). Leave `plugin.json` at 1.2.1: `land` raises it.
  Then land with the new step, from this branch's own copy of the scripts: `scripts/verify` as its own command, the independent review, the pull request titled `feat: raise the version on every merge that needs it (#31)`. `raise-version.sh` prints `raised 1.2.1 1.3.0` and commits `chore: release 1.3.0 (#31)`. Push, merge. `tag-version.sh` prints `tagged 1.3.0`. Set `pluginVersion` in `.claude/dev-workflow.json` wherever setup's rerun puts it. Confirm the tag with `git ls-remote --tags origin`, and tick the issue's criteria.
