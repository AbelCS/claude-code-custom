# Version tags: every version marked by a bare git tag

Issue: [#27](https://github.com/AbelCS/claude-code-custom/issues/27). Status: approved by the owner on 2026-11-21.

## Problem

The rules said "Releases follow SemVer". That mixed up two things. A version is the SemVer number of the code. A GitHub Release is a GitHub feature. A project that never enabled releases had versions and nothing marking them: no tag said which commit was 1.1.0. This repo was one of them, with three versions out and no tags.

Where releases were enabled, release-please wrote tags with a `v`, so a project's tags depended on how it was set up.

## Decisions

1. **A version and a GitHub Release are separate.** A version is the SemVer number of the code. A GitHub Release is optional, and comes on top.
2. **Every version of every project is marked by a git tag holding the bare version,** like `1.4.0`, never `v1.4.0`. Tags are plain git, so they work anywhere.
3. **GitHub Releases are only for projects that run `/dev-workflow:enable-releases`,** which sets up release-please. release-please then raises the version, tags it and publishes the Release. Its tags are bare too. In that case `land` doesn't tag.
4. **Without release-please, the version is raised in a pull request,** in the project's version file. After the merge, `land` tags the commit that set that version, and pushes the tag.
5. **`pre-push` lets a tag through without the check when its commit is already in the remote's default branch.** That commit was checked before it merged.
6. **release-please works only with GitHub,** because it uses GitHub's API. dev-workflow is already bound to GitHub, through issues, pull requests and `gh pr merge`, so this adds no new limit. The tags themselves are plain git.
7. **This repo follows the rule too.** Its past versions are tagged by hand, and from 1.2.0 on `land` tags them.
8. **The plugin goes to 1.2.0.** Projects pick up the new rule text and `versionFile` by running `/dev-workflow:setup` again.

## Design

### The version file

`versionFile` in `.claude/dev-workflow.json` is the file that holds the project's version, as a path from the repo's root. It is optional in the schema.

`detect.sh` reports the candidates it finds at the root as `versionFiles`: `package.json`, `pyproject.toml`, `Cargo.toml` and `VERSION`. Setup asks which one, recommending the candidate when there is only one, and takes any other path the person gives. A project with release-please doesn't need the field.

### `scripts/tag-version.sh`

A tested script in `plugins/dev-workflow/scripts/`. `land` runs it after the merge, from the updated default branch. In order:

1. `release-please-config.json` at the root: nothing to do, release-please tags. Exit 0.
2. No `versionFile` in the project file: say that versions aren't tagged, and that setting `versionFile` and running `/dev-workflow:setup` fixes it. Exit 0, so that `land` goes on and reports it.
3. Read the version from the file as committed on the default branch:
   - `.json`: the `version` field.
   - `.toml`: the `version = "..."` in `[project]`, `[package]`, `[tool.poetry]` or `[workspace.package]`, so a `version` in another table, such as a dependency's, isn't read.
   - any other file: its first line, trimmed.
4. A version that isn't SemVer is refused, with the value it found. A leading `v` is not SemVer.
5. Find the commit that set the version: walk back through the commits on the default branch that touched the file, until the version differs. The tag goes on the oldest commit that still has the current version. A commit that touched the file without changing the version is passed over.
6. Look at the tag named after the bare version:
   - Missing: create an annotated tag on that commit, and push it.
   - On that commit: nothing happens. This is the case after most merges, since most don't raise the version.
   - On another commit: report both commits and stop with an error. A tag is never moved or deleted.

The script says what it did in one line, for `land`'s report. A failed push is an error, and leaves the local tag for a retry.

### `pre-push`

For each pushed tag, the hook resolves the commit under it. If that commit is an ancestor of `refs/remotes/<remote>/<default>`, the tag passes and doesn't count as something to check. A push of nothing but such tags runs no check.

Any other tag keeps today's rule: its commit must be what's checked out, and the check runs. So does a tag pushed to a URL rather than a named remote, since there is no remote-tracking ref to compare with.

The template and this repo's copy in `.githooks/` stay identical.

### release-please

The config template sets `"include-v-in-tag": false` and `"include-component-in-tag": false`. `enable-releases` says that release-please raises the version, tags it bare and publishes the Release, and that `land` leaves tagging to it. Repos that already have a config aren't changed: the skill says what the existing one writes, as it does today.

### `land`

Step 7, after updating the default branch: run `tag-version.sh`, read what it printed, and put it in the report. An error from it is reported, not worked around.

### The rules

The workflow rules in `AGENTS.md`, in the template and here, replace "Releases follow SemVer" with: versions follow SemVer, each one is tagged with its bare number, and GitHub Releases are optional, through `/dev-workflow:enable-releases`.

### This repo

- `versionFile` is `plugins/dev-workflow/.claude-plugin/plugin.json`. Releases aren't enabled, so `land` tags.
- The past versions are tagged by hand, on the commits that set them: `1.0.0` on `bff96fb`, `1.1.0` on `19023e0`, `1.1.1` on `c4fd045`. They are pushed once the new `pre-push` rule is in the checkout, since none of them is what's checked out.
- `1.2.0` is tagged by `land` after this merges.
- With one plugin in the marketplace, bare tags are enough. A second plugin would need the plugin's name in the tag. That is decided then.

## Out of scope

- Choosing the next version automatically without release-please. A person or the agent raises it in the pull request.
- GitLab or Bitbucket support.
- Changelogs without release-please.

## Known limits

Both were found in the independent review and left on purpose: each is rare, and its fix costs more than the harm it prevents.

- **`main` rewritten on GitHub after the last fetch.** `pre-push` judges a tag by the local copy of the remote's default branch. If `main` was force-pushed since, a tag on a commit that left it still goes out without the check. That commit was checked when it merged, and the workflow never force-pushes `main`. Asking GitHub on every tag push would cost a network call each time.
- **TOML multiline strings.** The `.toml` reader works line by line. A multiline string holding text like `[project]` and `version = "..."` could be read as the version. Reading TOML properly needs a real parser, which POSIX `sh` doesn't have, and the plugin's scripts don't depend on Python or Node.
