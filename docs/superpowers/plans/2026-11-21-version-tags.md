# Version tags Implementation Plan

**Goal:** Every version is marked by a git tag holding the bare version. `land` tags it when the project has no release-please, and release-please tags it bare when it has.

**Spec:** `docs/superpowers/specs/2026-11-21-version-tags-design.md`. Read it first.

**Delivery:** One issue, [#27](https://github.com/AbelCS/claude-code-custom/issues/27), one branch, `feat/27-version-tags`, one squash-merged pull request. Each commit subject ends with `(#27)`.

## Constraints

- Test first, in every step. Run the one test file, then `scripts/check` before moving on.
- Scripts are POSIX `sh`. `pre-push` must not need `jq`. `tag-version.sh` may.
- Wording about a framework stays in `plugins/dev-workflow/stacks/`. The version file candidates are file names, not framework wording.
- No AI attribution. Nothing private named.

Paths below are under `plugins/dev-workflow/` unless they start with `tests/`, `docs/`, `.githooks/`, `.claude/` or name a root file.

## Steps

- [ ] **1. `pre-push`: a tag on a merged commit passes without the check.**
  Files: `skills/setup/templates/githooks/pre-push`, `.githooks/pre-push` (kept identical), `tests/githooks/pre-push.test.sh`.
  Tests: a tag, light and annotated, on a commit in `refs/remotes/<remote>/<default>` passes and the check doesn't run. A tag on an unmerged commit that isn't checked out is still refused. A merged tag pushed with a branch still runs the check for the branch. `tests/repo.test.sh` confirms the two copies match.

- [ ] **2. `versionFile` in the project file, and setup asks for it.**
  Files: `skills/setup/references/project-file.schema.json`, `skills/setup/references/answers.md`, `scripts/setup/detect.sh` (a `versionFiles` field), `skills/setup/SKILL.md`.
  Tests: `tests/setup/project-file.test.sh` accepts a path and refuses an empty or absolute one. `tests/setup/detect.test.sh` lists `package.json`, `pyproject.toml` and `Cargo.toml` when at the root, and `[]` when none is. `tests/setup/run.test.sh` writes the answer into the project file. `tests/skills/content.test.sh` if it pins setup's questions.

- [ ] **3. `scripts/tag-version.sh`.**
  Files: `scripts/tag-version.sh`, `tests/tag-version.test.sh`.
  Tests, each in its own temp repo with a bare remote: a new version tagged, annotated, on the commit that set it, and pushed, also when later commits touched the file without changing the version. An existing tag on that commit left alone. A tag on another commit reported and not moved. No `versionFile` reported, exit 0. `release-please-config.json` present: nothing to do. A version that isn't SemVer refused, including `v1.2.0`. One case each for `.json`, `.toml` and a plain file.

- [ ] **4. `land` runs it.**
  Files: `skills/land/SKILL.md` (step 7, and the report in step 8).
  Tests: `tests/skills/content.test.sh` checks that `land` names the script. The `land-fires` and `land-quiet` evals are unchanged.

- [ ] **5. release-please writes bare tags.**
  Files: `skills/enable-releases/templates/release-please-config.json`, `skills/enable-releases/SKILL.md`.
  Tests: no test reads the release templates today, so add one, `tests/skills/release-templates.test.sh`, asserting both settings are `false`. The old-setup fixture in `tests/verify_only/fixtures.test.sh` keeps its `"include-v-in-tag": true`, since existing configs aren't changed.

- [ ] **6. The rules.**
  Files: `skills/setup/templates/agents/workflow.md`, `AGENTS.md` (the Workflow line, and the Testing line about what `pre-push` lets through).
  Tests: `tests/setup/agents-md.test.sh` and `tests/repo.test.sh`. Update any expected text they hold. Check that a project with the old, unedited section gets the new one on a rerun.

- [ ] **7. Version 1.2.0 and the docs.**
  Files: `.claude-plugin/plugin.json` (`version`), `README.md` (upgrade notes for 1.2.0, the project file's settings, the line on what a second release run tags), `docs/workflow-guide.md` and `docs/hook-behaviour.md` where they describe landing, releases or `pre-push`, `.claude/dev-workflow.json` (`versionFile`, `pluginVersion`), `docs/decisions.md` (done with the spec).
  Tests: `tests/marketplace.test.sh` pins the version, `tests/readme.test.sh`, `tests/repo.test.sh`. Then `scripts/check`.

- [ ] **8. Tags.**
  By hand, once step 1 is in the checkout: annotated tags `1.0.0` on `bff96fb`, `1.1.0` on `19023e0`, `1.1.1` on `c4fd045`, pushed on their own. Confirm with `git ls-remote --tags origin`.
  Then land: `scripts/verify` as its own command, the independent review if the change is over the threshold, the pull request, the merge. `land` runs `tag-version.sh`, which tags `1.2.0` on the squash commit. Confirm all four tags on GitHub, and tick the issue's criteria.
