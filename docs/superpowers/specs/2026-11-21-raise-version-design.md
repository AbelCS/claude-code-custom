# Raising the version: every merge that changes behaviour gets the next number

Issue: [#31](https://github.com/AbelCS/claude-code-custom/issues/31). Status: approved by the owner on 2026-11-21. Builds on [version tags](2026-11-21-version-tags-design.md).

## Problem

The version-tags spec left raising the version to "a person or the agent, in the pull request". Nothing said when, or by how much. So most merges raised nothing: a feature landed on the default branch under the number of the version before it, and the tag for that number pointed at older code. The version stopped saying what was on the default branch.

Two open branches could also both pick the same next number, each from its own stale copy of the file.

## Decisions

1. **Without release-please, every merge that changes behaviour raises the version.** The version and its tag then always match what's on the default branch.
2. **With release-please, nothing changes.** It batches merges into a release when a person runs it. That is its design: forcing it per merge would mean two runs and an extra pull request for every merge. semantic-release is the per-merge tool in that world. release-please and Changesets batch.
3. **The bump comes from the pull request title,** which becomes the squash commit's subject. `feat` raises the minor, `fix` and `perf` the patch, and a `!` before the colon the major. Any other type raises nothing: `docs`, `chore`, `test`, `refactor`, `ci`, `build`, `style`, `revert`.
4. **Before 1.0.0, one step lower:** a breaking change raises the minor, a feature the patch, a fix the patch. This matches `bump-minor-pre-major` and `bump-patch-for-minor-pre-major` in the release-please template, so both paths agree.
5. **A `BREAKING CHANGE` footer doesn't count.** The squash message's body is blank, so `!` is the only signal.
6. **A pre-release version, like `2.0.0-rc.1`, isn't raised automatically.** What comes after a pre-release is a person's call: the next candidate, or the release itself. `land` says so and leaves it.
7. **The next version is worked out from the version on origin's default branch, at merge time.** So two open branches can't both claim the same number. If the default branch has moved, `land` merges it into the branch first. A merge, not a rebase, so nothing already pushed is rewritten.
8. **It is written as one commit on the branch, before the merge:** `chore: release <version> (#<issue>)`. The squash commit then holds the code and its version together, and the existing tag step tags it.
9. **Tested scripts do the mechanical parts.** One shared library reads and writes the version file, so `tag-version.sh` and the new script can't disagree.
10. **Only `versionFile` is written.** A lock file that repeats the version, such as `package-lock.json`, follows on the next install. That is stack tooling, outside the plugin's generic scripts.
11. **This repo follows it too.** Its next `feat` merge raises `plugins/dev-workflow/.claude-plugin/plugin.json`. This feature is the first: 1.2.1 becomes 1.3.0.

## Design

### `scripts/lib/version-file.sh`

A library, sourced, never run. It holds what `tag-version.sh` does today, moved without changing it, plus writing:

- **Read:** the version in a file's content, by the file's name. A `.json` file's `version` field, a `.toml` file's `version` in `[project]`, `[package]`, `[tool.poetry]` or `[workspace.package]`, and any other file's first line, trimmed.
- **Check:** the SemVer 2.0.0 grammar, bare, with no `v`.
- **Write:** replace the old version's text with the new one, in place. Nothing else in the file changes: not the indentation, the key order, the line endings or the last newline. Then read the result back. If the reader doesn't see the new version there, the file is left as it was and the write fails.

`tag-version.sh` sources it and keeps its behaviour. Its tests stay as they are.

### `scripts/land/raise-version.sh <root> <title>`

One script works out the next version and writes it, since the first is a few lines of the second. `land` runs it on the pull request's branch, with the pull request's title. It prints one line. In order:

1. Read the type and the `!` from the title, with or without a scope. A title that isn't a Conventional Commit is refused.
2. `release-please-config.json` at the root: `skip release-please`. No `versionFile` in the project file: `skip no-version-file`.
3. Uncommitted changes to tracked files are refused: they would go into the release commit.
4. Fetch origin's default branch. If the branch doesn't hold its tip, refuse, and say to merge it in first.
5. Read the version from the file as committed on origin's default branch. A version that isn't SemVer is refused.
6. The file on the branch holds another version: `skip already-raised`, naming both. A person raised it by hand in this pull request, and that stands.
7. A pre-release or build part: `skip pre-release`, naming the version.
8. A type that raises nothing: `unchanged <type>`.
9. Otherwise raise the part the mapping names, set the parts after it to 0, write the file, and commit it alone as `chore: release <version> (#<issue>)`, the issue from the branch's name. Print `raised <old> <new>`.

The commit goes through `commit-msg` like any other. A skip or `unchanged` exits 0 with no commit. A refusal exits 1 and leaves the file and the branch as they were.

### `land`

A new step between the pull request and the merge, once everything is green:

1. Run `raise-version.sh . "<title>"` with the pull request's title, and read what it printed.
2. If it says the default branch has moved, `git merge origin/<default>`, run verify again, on its own, and run the script again.
3. On `raised`, push. `pre-push` runs the check on the release commit.
4. Merge, as today. After the merge, `tag-version.sh` prints `tagged` for the new version. The report names it, or passes on the `skip` or `unchanged` line.

A person can still raise the version by hand, in any pull request: to a number the title doesn't give, or in a `chore` that should go out. The script leaves it, and the tag step tags it as before.

### The rules and the docs

The workflow rules, in the template and here, say that without release-please `land` raises the version from the pull request's title before the merge. The README, the workflow guide and the earlier spec's "you raise the version in a pull request" wording follow.

### This repo

`tests/marketplace.test.sh` pins the version as `1.2.1`. It changes to check that the version is bare SemVer, or every raise would need a test edit. This pull request's title is a `feat`, so `land` raises 1.2.1 to 1.3.0 and tags it.

## Out of scope

- Raising the version per merge with release-please, and semantic-release or Changesets support.
- Lock files and any other file that repeats the version.
- Changelogs without release-please.
- More than one version file, such as a monorepo's packages.

## Known limits

- **TOML.** The limit in the version-tags spec applies to writing too: the `.toml` code works line by line, so a multiline string holding text like `[project]` and `version = "..."` could be taken for the version. The read-back catches a write that the reader then disagrees with, not this one.
- **A merge landing between the fetch and the merge.** If another pull request raises the version in those seconds, both squash commits can hold the same number, and git merges the identical line without a conflict. `tag-version.sh` then prints `done` for a commit that isn't this merge, where `land` expected `tagged`. `land` reports that. Closing the gap would need a lock on the default branch, which GitHub doesn't offer here.
- **A JSON file with an earlier `"version"` holding the same text.** The write replaces text, not a parsed field. If the first match isn't the top-level field, the read-back fails and the file is left as it was, for a person to raise.
