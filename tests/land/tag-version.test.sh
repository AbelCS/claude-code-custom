#!/bin/sh
# tag-version.sh <root>: after land's merge, tags the commit on the remote's default
# branch that set the version in the project's versionFile, with the bare version, and
# pushes the tag. Real git against a bare remote; nothing here reaches GitHub.

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
# shellcheck source=tests/lib/assert.sh
. "$ROOT/tests/lib/assert.sh"

TV="$ROOT/plugins/dev-workflow/scripts/land/tag-version.sh"

# The owner's own git settings must not change a result.
GIT_CONFIG_GLOBAL=/dev/null
GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL GIT_CONFIG_NOSYSTEM

# Sets $repo and $origin to a new repo whose project file names $1 as its version file,
# with a bare remote that has its main.
new_fixture() { # <version file, or "" for none>
  base=$(tmp_dir)
  repo=$base/repo
  origin=$base/origin.git
  git init -q --bare -b main "$origin"
  new_repo "$repo"
  git -C "$repo" remote add origin "$origin"
  mkdir -p "$repo/.claude"
  if [ -n "$1" ]; then
    printf '{ "schemaVersion": 1, "pluginVersion": "1.2.0", "commands": { "check": "true" }, "versionFile": "%s" }\n' "$1" >"$repo/.claude/dev-workflow.json"
  else
    printf '{ "schemaVersion": 1, "pluginVersion": "1.2.0", "commands": { "check": "true" } }\n' >"$repo/.claude/dev-workflow.json"
  fi
  git -C "$repo" add .claude
  git -C "$repo" commit -q -m 'chore: set up'
}

commit_file() { # <path> <contents>: commits it, and prints the commit.
  mkdir -p "$(dirname "$repo/$1")"
  printf '%s\n' "$2" >"$repo/$1"
  git -C "$repo" add -- ":(literal)$1"
  git -C "$repo" commit -q -m "chore: change $1"
  git -C "$repo" rev-parse HEAD
}

empty_commit() {
  git -C "$repo" commit -q --allow-empty -m 'chore: something else'
}

publish() {
  git -C "$repo" push -q origin main
}

run() {
  sh "$TV" "$repo"
}

remote_tag() { # <tag>: the commit the remote's tag points at, or nothing.
  git -C "$origin" rev-parse -q --verify "refs/tags/$1^{commit}"
}

# --- A new version is tagged on the commit that set it, not on the latest one

new_fixture package.json
commit_file package.json '{ "name": "app", "version": "1.0.0" }' >/dev/null
set_it=$(commit_file package.json '{ "name": "app", "version": "1.1.0" }')
# Touches the file without changing the version, then something else entirely.
commit_file package.json '{ "name": "app", "version": "1.1.0", "private": true }' >/dev/null
empty_commit
publish
out=$(run)
assert_exit 0 run
assert_contains "$out" "tagged 1.1.0 $set_it"
assert_exit 0 test "$(remote_tag 1.1.0)" = "$set_it"
# Annotated, so it carries who tagged it and when.
assert_exit 0 test "$(git -C "$repo" cat-file -t refs/tags/1.1.0)" = tag
assert_exit 1 test -n "$(remote_tag 1.0.0)"

# --- Already tagged: nothing to do, which is what most merges find

empty_commit
publish
out=$(run)
assert_contains "$out" "done 1.1.0 $set_it"
assert_exit 0 test "$(remote_tag 1.1.0)" = "$set_it"

# On the remote only, as in a fresh clone: fetched, not tagged again.
git -C "$repo" tag -d 1.1.0 >/dev/null
out=$(run)
assert_contains "$out" "done 1.1.0 $set_it"
assert_exit 0 test "$(git -C "$repo" rev-parse 'refs/tags/1.1.0^{commit}')" = "$set_it"

# --- A tag on another commit is reported, and never moved

git -C "$repo" push -q origin :refs/tags/1.1.0
git -C "$repo" tag -d 1.1.0 >/dev/null
git -C "$repo" tag 1.1.0 HEAD
assert_exit 1 run
out=$(run 2>&1)
assert_contains "$out" '1.1.0'
assert_contains "$out" "$set_it"
assert_exit 0 test "$(git -C "$repo" rev-parse 'refs/tags/1.1.0^{commit}')" = "$(git -C "$repo" rev-parse HEAD)"
assert_exit 1 test -n "$(remote_tag 1.1.0)"

# The same when it's the remote's tag that's elsewhere.
git -C "$repo" push -q origin refs/tags/1.1.0
git -C "$repo" tag -d 1.1.0 >/dev/null
assert_exit 1 run
assert_exit 0 test "$(remote_tag 1.1.0)" = "$(git -C "$repo" rev-parse HEAD)"

# --- Given the merge's own commit, it tags what that merge set, even after later ones

new_fixture package.json
commit_file package.json '{ "version": "1.0.0" }' >/dev/null
first=$(commit_file package.json '{ "version": "1.1.0" }')
second=$(commit_file package.json '{ "version": "1.2.0" }')
publish
assert_contains "$(sh "$TV" "$repo" "$first")" "tagged 1.1.0 $first"
assert_contains "$(sh "$TV" "$repo" "$second")" "tagged 1.2.0 $second"
# A merge that didn't change the version finds the one before it already tagged.
empty_commit
publish
assert_contains "$(sh "$TV" "$repo" "$(git -C "$repo" rev-parse HEAD)")" "done 1.2.0 $second"
# A commit that isn't on the remote's default branch isn't a merge.
git -C "$repo" switch -q -c side
side=$(commit_file package.json '{ "version": "9.0.0" }')
assert_exit 1 sh "$TV" "$repo" "$side"
assert_exit 1 sh "$TV" "$repo" not-a-commit
assert_exit 1 test -n "$(git -C "$repo" tag -l 9.0.0)"
git -C "$repo" switch -q main

# --- A history with merge commits: the default branch's own line, not a side branch's

new_fixture VERSION
commit_file VERSION 1.0.0 >/dev/null
git -C "$repo" switch -q -c side
commit_file VERSION 1.1.0 >/dev/null
commit_file other.txt x >/dev/null
git -C "$repo" switch -q main
empty_commit
git -C "$repo" merge -q --no-ff -m 'Merge side' side
merge=$(git -C "$repo" rev-parse HEAD)
publish
assert_contains "$(run)" "tagged 1.1.0 $merge"

# --- A shallow clone can't show where the version was set, so it stops

new_fixture VERSION
commit_file VERSION 1.0.0 >/dev/null
empty_commit
publish
shallow=$(tmp_dir)/shallow
git clone -q --depth 1 "file://$origin" "$shallow"
cp -R "$repo/.claude" "$shallow/"
git -C "$shallow" config user.name Test
git -C "$shallow" config user.email test@example.com
assert_exit 1 sh "$TV" "$shallow"
assert_contains "$(sh "$TV" "$shallow" 2>&1)" 'shallow'
assert_exit 1 test -n "$(git -C "$origin" tag -l)"

# --- Fetch settings that prune tags don't remove a local tag before it's checked

new_fixture VERSION
set_it=$(commit_file VERSION 1.0.0)
empty_commit
publish
git -C "$repo" tag 1.0.0 HEAD
git -C "$repo" config fetch.prune true
git -C "$repo" config fetch.pruneTags true
assert_exit 1 run
assert_exit 0 test "$(git -C "$repo" rev-parse 'refs/tags/1.0.0^{commit}')" = "$(git -C "$repo" rev-parse HEAD)"
assert_exit 1 test -n "$(remote_tag 1.0.0)"
assert_exit 0 test -n "$set_it"

# --- Only what's on the remote's default branch counts

new_fixture package.json
commit_file package.json '{ "version": "2.0.0" }' >/dev/null
publish
unpushed=$(commit_file package.json '{ "version": "2.1.0" }')
out=$(run)
assert_contains "$out" 'tagged 2.0.0'
assert_exit 1 test -n "$(remote_tag 2.1.0)"
assert_exit 1 test -n "$(git -C "$repo" tag -l 2.1.0)"
assert_exit 0 test -n "$unpushed"

# --- Other version files

# pyproject.toml: the version in [project], not one in another table before it.
new_fixture pyproject.toml
set_it=$(commit_file pyproject.toml '[tool.other]
version = "9.9.9"

[project]
name = "app"
version = "0.3.0"')
publish
assert_contains "$(run)" "tagged 0.3.0 $set_it"

# Cargo.toml: the [package] table's.
new_fixture Cargo.toml
set_it=$(commit_file Cargo.toml '[package]
name = "app"
version = "0.4.1"

[dependencies]
serde = { version = "1" }')
publish
assert_contains "$(run)" "tagged 0.4.1 $set_it"

# A comment after the table's name, and single quotes, are TOML too.
new_fixture pyproject.toml
set_it=$(commit_file pyproject.toml "[project]  # the package
name = 'app'
version = '0.5.0'")
publish
assert_contains "$(run)" "tagged 0.5.0 $set_it"

# A file name that git would otherwise read as a pattern.
new_fixture ':VERSION'
set_it=$(commit_file ':VERSION' 0.6.0)
publish
assert_contains "$(run)" "tagged 0.6.0 $set_it"

# A plain file holding the version, in a subfolder.
new_fixture plugins/app/VERSION
set_it=$(commit_file plugins/app/VERSION '3.0.0-rc.1')
publish
assert_contains "$(run)" "tagged 3.0.0-rc.1 $set_it"

# A JSON file elsewhere, such as a plugin's manifest.
new_fixture plugins/app/.claude-plugin/plugin.json
set_it=$(commit_file plugins/app/.claude-plugin/plugin.json '{ "name": "app", "version": "1.2.0" }')
publish
assert_contains "$(run)" "tagged 1.2.0 $set_it"

# --- Nothing to tag, said plainly, and not an error

new_fixture ''
commit_file package.json '{ "version": "1.0.0" }' >/dev/null
publish
assert_exit 0 run
out=$(run)
assert_contains "$out" 'skip no-version-file'
assert_exit 1 test -n "$(git -C "$repo" tag -l)"

# release-please tags versions itself.
new_fixture package.json
commit_file package.json '{ "version": "1.0.0" }' >/dev/null
commit_file release-please-config.json '{}' >/dev/null
publish
assert_exit 0 run
assert_contains "$(run)" 'skip release-please'
assert_exit 1 test -n "$(git -C "$repo" tag -l)"

# --- What can't be tagged

# Not a bare SemVer version, including the identifier rules: no leading zero in a
# number, and no empty part.
for bad in v1.2.0 1.2 'latest' '' 01.2.3 1.2.3-01 1.2.3-rc.01 1.2.3-rc..1 1.2.3-rc. 1.2.3- 1.2.3+ 1.2.3+a..b; do
  new_fixture VERSION
  commit_file VERSION "$bad" >/dev/null
  publish
  assert_exit 1 run
  assert_contains "$(run 2>&1)" 'SemVer'
  assert_exit 1 test -n "$(git -C "$repo" tag -l)"
done

# Valid SemVer, prerelease and build parts included.
for good in 1.2.3-0 1.2.3-rc.1 1.2.3-alpha-1 1.2.3-0a.1 1.2.3+build.01 1.2.3-rc.1+sha.5114f85; do
  new_fixture VERSION
  commit_file VERSION "$good" >/dev/null
  publish
  assert_contains "$(run)" "tagged $good"
done

# SemVer, but not a name git allows for a tag: said as that, not as bad SemVer.
new_fixture VERSION
commit_file VERSION 1.2.3+ci.lock >/dev/null
publish
assert_exit 1 run
assert_contains "$(run 2>&1)" 'tag name'

# --- origin's default branch has changed: the project file is out of date, so it stops

new_fixture VERSION
commit_file VERSION 1.0.0 >/dev/null
publish
git -C "$repo" push -q origin main:trunk
git -C "$origin" symbolic-ref HEAD refs/heads/trunk
assert_exit 1 run
assert_contains "$(run 2>&1)" 'trunk'
assert_exit 1 test -n "$(remote_tag 1.0.0)"

# JSON without a version.
new_fixture package.json
commit_file package.json '{ "name": "app" }' >/dev/null
publish
assert_exit 1 run

# The version file isn't on the default branch.
new_fixture package.json
empty_commit
publish
assert_exit 1 run
assert_contains "$(run 2>&1)" 'package.json'

# Nothing pushed yet, so there's no remote branch to read.
new_fixture package.json
commit_file package.json '{ "version": "1.0.0" }' >/dev/null
assert_exit 1 run

# --- Usage

assert_exit 2 sh "$TV"
assert_exit 2 sh "$TV" "$(tmp_dir)/missing"
# A folder with no project file isn't a set-up project.
plain=$(tmp_dir)
new_repo "$plain"
assert_exit 2 sh "$TV" "$plain"
