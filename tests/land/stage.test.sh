#!/bin/sh
# stage.sh <root>: the project's stage, for land, from the version on origin's default
# branch: early before 1.0.0, stable from it, and stable when it can't tell.

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
# shellcheck source=tests/lib/assert.sh
. "$ROOT/tests/lib/assert.sh"

ST="$ROOT/plugins/dev-workflow/scripts/land/stage.sh"

GIT_CONFIG_GLOBAL=/dev/null
GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL GIT_CONFIG_NOSYSTEM

# fixture <version, or "" for no version file> [project file's versionFile]
fixture() {
  base=$(tmp_dir)
  repo=$base/repo
  git init -q --bare -b main "$base/origin.git"
  new_repo "$repo"
  git -C "$repo" remote add origin "$base/origin.git"
  mkdir "$repo/.claude"
  printf '{ "commands": { "check": "true" }, "versionFile": "%s" }\n' "${2-VERSION}" >"$repo/.claude/dev-workflow.json"
  [ -z "$1" ] || printf '%s\n' "$1" >"$repo/VERSION"
  git -C "$repo" add -A
  git -C "$repo" commit -q -m 'chore: start'
  git -C "$repo" push -q origin main
  git -C "$repo" switch -q -c feat/1-x
}

stage() {
  sh "$ST" "$repo"
}

fixture 0.4.2
assert_exit 0 test "$(stage)" = 'early 0.4.2'
fixture 1.0.0-rc.1
assert_exit 0 test "$(stage)" = 'early 1.0.0-rc.1'
fixture 1.0.0
assert_exit 0 test "$(stage)" = 'stable 1.0.0'
fixture 3.2.1
assert_exit 0 test "$(stage)" = 'stable 3.2.1'

# It's origin's version that counts, not a raise on this branch.
fixture 0.9.0
printf '1.0.0\n' >"$repo/VERSION"
git -C "$repo" commit -q -am 'chore: release 1.0.0 (#1)'
assert_exit 0 test "$(stage)" = 'early 0.9.0'

# A version file this branch adds: its version, as origin has none yet.
fixture ''
printf '0.1.0\n' >"$repo/VERSION"
git -C "$repo" add VERSION
git -C "$repo" commit -q -m 'chore: a version (#1)'
assert_exit 0 test "$(stage)" = 'early 0.1.0'

# No version to read: stable, the stricter rules, since it can't tell.
fixture 0.4.2 ''
jq 'del(.versionFile)' "$repo/.claude/dev-workflow.json" >"$base/pf"
cp "$base/pf" "$repo/.claude/dev-workflow.json"
assert_exit 0 test "$(stage)" = 'stable unknown'
fixture 'not a version'
assert_exit 0 test "$(stage)" = 'stable unknown'

assert_exit 2 sh "$ST"
assert_exit 2 sh "$ST" "$(tmp_dir)"
