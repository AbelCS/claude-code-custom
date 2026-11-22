#!/bin/sh
# raise-version.sh <root> <title>: before land merges, raises the version in the project's
# versionFile from the pull request title's Conventional Commit type, as one commit on the
# branch. Real git against a bare remote; nothing here reaches GitHub.

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
# shellcheck source=tests/lib/assert.sh
. "$ROOT/tests/lib/assert.sh"

RV="$ROOT/plugins/dev-workflow/scripts/land/raise-version.sh"

# The owner's own git settings must not change a result.
GIT_CONFIG_GLOBAL=/dev/null
GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL GIT_CONFIG_NOSYSTEM

# new_fixture <version file> <contents> [branch]: main holds the project file and the
# version file, pushed to a bare origin; the branch, feat/7-x by default, has one commit.
new_fixture() {
  base=$(tmp_dir)
  repo=$base/repo
  origin=$base/origin.git
  git init -q --bare -b main "$origin"
  new_repo "$repo"
  git -C "$repo" remote add origin "$origin"
  mkdir -p "$repo/.claude" "$(dirname "$repo/$1")"
  printf '{ "schemaVersion": 1, "pluginVersion": "1.3.0", "commands": { "check": "true" }, "versionFile": "%s" }\n' "$1" >"$repo/.claude/dev-workflow.json"
  printf '%s\n' "$2" >"$repo/$1"
  git -C "$repo" add -A
  git -C "$repo" commit -q -m 'chore: set up'
  git -C "$repo" push -q origin main
  git -C "$repo" switch -q -c "${3:-feat/7-x}"
  git -C "$repo" commit -q --allow-empty -m 'feat: the work (#7)'
}

run() { # <title>
  sh "$RV" "$repo" "$1"
}

head_subject() {
  git -C "$repo" log -1 --format=%s
}

commits_on_branch() {
  git -C "$repo" rev-list --count origin/main..HEAD
}

# raises <old> <title> <new>: in a package.json, the title raises old to new, as one
# commit that changes only the version.
raises() {
  new_fixture package.json "{
  \"name\": \"app\",
  \"version\": \"$1\",
  \"private\": true
}"
  out=$(run "$2")
  assert_contains "$out" "raised $1 $3"
  assert_exit 0 test "$(jq -r .version "$repo/package.json")" = "$3"
  assert_exit 0 test "$(head_subject)" = "chore: release $3 (#7)"
  assert_exit 0 test "$(commits_on_branch)" = 2
  # Only the version's own line changed, and the rest of the file is as it was.
  assert_exit 0 test "$(git -C "$repo" diff HEAD~1 --numstat -- package.json)" = "$(printf '1\t1\tpackage.json')"
  assert_exit 0 test -z "$(git -C "$repo" status --porcelain)"
}

# unchanged <old> <title> <text>: no commit, no change, and it says why.
unchanged() {
  new_fixture package.json "{ \"version\": \"$1\" }"
  out=$(run "$2")
  assert_exit 0 run "$2"
  assert_contains "$out" "$3"
  assert_exit 0 test "$(jq -r .version "$repo/package.json")" = "$1"
  assert_exit 0 test "$(commits_on_branch)" = 1
}

# --- The bump from the title, the same as release-please's

raises 1.2.3 'feat: add search (#7)' 1.3.0
raises 1.2.3 'feat(search): add filters (#7)' 1.3.0
raises 1.2.3 'fix: an empty cart (#7)' 1.2.4
raises 1.2.3 'perf: a faster list (#7)' 1.2.4
raises 1.2.3 'feat!: a new API (#7)' 2.0.0
raises 1.2.3 'fix(api)!: drop the old field (#7)' 2.0.0
raises 1.9.9 'feat: add search (#7)' 1.10.0

# Before 1.0.0, one step lower: a feature is a patch, and a breaking change a minor.
raises 0.4.2 'feat: add search (#7)' 0.4.3
raises 0.4.2 'fix: an empty cart (#7)' 0.4.3
raises 0.4.2 'feat!: a new API (#7)' 0.5.0

# Other types change nothing.
for type in docs chore test refactor ci build style revert; do
  unchanged 1.2.3 "$type: something (#7)" "unchanged $type"
done

# --- What it leaves to a person

# A pre-release: what comes next is a person's call.
unchanged 2.0.0-rc.1 'feat: add search (#7)' 'skip pre-release'

# Raised by hand in this pull request already.
new_fixture VERSION 1.2.3
printf '1.5.0\n' >"$repo/VERSION"
git -C "$repo" commit -q -am 'chore: release 1.5.0 (#7)'
out=$(run 'feat: add search (#7)')
assert_contains "$out" 'skip already-raised: 1.5.0'
assert_exit 0 test "$(commits_on_branch)" = 2

# Lower than origin's, or no longer a version at all: refused, not taken as raised by hand.
new_fixture VERSION 1.3.0
printf '1.2.9\n' >"$repo/VERSION"
git -C "$repo" commit -q -am 'chore: lower it (#7)'
assert_exit 1 run 'feat: add search (#7)'
assert_contains "$(run 'feat: add search (#7)' 2>&1)" 'lower'
new_fixture VERSION 1.3.0
printf '1.3.0-rc.1\n' >"$repo/VERSION"
git -C "$repo" commit -q -am 'chore: a pre-release of the same (#7)'
assert_exit 1 run 'feat: add search (#7)'
new_fixture package.json '{ "version": "1.3.0" }'
printf '{ "name": "app" }\n' >"$repo/package.json"
git -C "$repo" commit -q -am 'chore: lose the version (#7)'
assert_exit 1 run 'feat: add search (#7)'

# A first version file, added in this pull request: nothing on origin to raise from, so
# its version is the first one, tagged after the merge.
new_fixture VERSION 1.2.3
git -C "$repo" switch -q main
jq 'del(.versionFile)' "$repo/.claude/dev-workflow.json" >"$base/pf.json"
cp "$base/pf.json" "$repo/.claude/dev-workflow.json"
git -C "$repo" rm -q VERSION
git -C "$repo" commit -q -am 'chore: no version yet'
git -C "$repo" push -q origin main
git -C "$repo" switch -q -c chore/8-versions
printf '0.1.0\n' >"$repo/VERSION"
jq '.versionFile = "VERSION"' "$base/pf.json" >"$repo/.claude/dev-workflow.json"
git -C "$repo" add -A
git -C "$repo" commit -q -m 'chore: add a version (#8)'
assert_exit 0 run 'chore: add a version (#8)'
assert_contains "$(run 'feat: add a version (#8)')" 'skip first-version: 0.1.0'
assert_exit 0 test "$(git -C "$repo" rev-list --count origin/main..HEAD)" = 1

# --- The readiness gate at 1.0.0

# gate_fixture <old> <new>: origin holds old, and the branch raised it by hand to new.
gate_fixture() {
  new_fixture VERSION "$1"
  printf '%s\n' "$2" >"$repo/VERSION"
  git -C "$repo" commit -q -am "chore: release $2 (#7)"
}
readiness() { # <text of docs/readiness.md>: committed on the branch.
  mkdir -p "$repo/docs"
  printf '%s\n' "$1" >"$repo/docs/readiness.md"
  git -C "$repo" add docs/readiness.md
  git -C "$repo" commit -q -m 'docs: readiness (#7)'
}

# Crossing to 1.0.0 or above needs that version's readiness entry.
gate_fixture 0.9.4 1.0.0
assert_exit 1 run 'feat: go stable (#7)'
assert_contains "$(run 'feat: go stable (#7)' 2>&1)" 'readiness'
readiness '# Readiness

## 0.9.0, 2026-10-01

## 1.0.1, 2026-11-22'
assert_exit 1 run 'feat: go stable (#7)'
readiness '# Readiness

## 1.0.0, 2026-11-22

| Item | Outcome | Why |
|---|---|---|'
assert_contains "$(run 'feat: go stable (#7)')" 'skip already-raised: 1.0.0'

gate_fixture 0.12.0 2.0.0
assert_exit 1 run 'feat!: go stable (#7)'

# An entry only on disk, not committed, isn't in the merge, so it doesn't count.
gate_fixture 0.9.4 1.0.0
mkdir -p "$repo/docs"
printf '## 1.0.0, 2026-11-22\n' >"$repo/docs/readiness.md"
assert_exit 1 run 'feat: go stable (#7)'

# A heading that only starts with the version isn't its entry.
gate_fixture 0.9.4 1.0.0
readiness '## 1.0.0-rc.1, 2026-11-20'
assert_exit 1 run 'feat: go stable (#7)'

# A release candidate comes before 1.0.0, in SemVer's order: the candidate isn't gated,
# and the step from it to 1.0.0 is.
gate_fixture 0.9.4 1.0.0-rc.1
assert_contains "$(run 'feat: a candidate (#7)')" 'skip already-raised: 1.0.0-rc.1'
gate_fixture 1.0.0-rc.2 1.0.0
assert_exit 1 run 'feat: go stable (#7)'
readiness '## 1.0.0, 2026-11-22'
assert_contains "$(run 'feat: go stable (#7)')" 'skip already-raised: 1.0.0'
# Later candidates of later majors are past the gate.
gate_fixture 2.0.0-rc.1 2.0.0
assert_contains "$(run 'feat: a new major (#7)')" 'skip already-raised: 2.0.0'

# Raises that don't cross 1.0.0 aren't gated.
gate_fixture 1.2.3 2.0.0
assert_contains "$(run 'feat!: a new API (#7)')" 'skip already-raised: 2.0.0'
gate_fixture 0.4.0 0.9.0
assert_contains "$(run 'feat: more (#7)')" 'skip already-raised: 0.9.0'
raises 1.9.9 'feat!: a new API (#7)' 2.0.0

# --- Skipped, saying why# --- Skipped, saying why

new_fixture package.json '{ "version": "1.2.3" }'
printf '{}\n' >"$repo/release-please-config.json"
git -C "$repo" add release-please-config.json
git -C "$repo" commit -q -m 'chore: enable release-please (#7)'
assert_contains "$(run 'feat: add search (#7)')" 'skip release-please'
assert_exit 0 test "$(commits_on_branch)" = 2

# A release-please config that isn't committed doesn't count: the merge won't have it.
new_fixture package.json '{ "version": "1.2.3" }'
printf '{}\n' >"$repo/release-please-config.json"
assert_contains "$(run 'feat: add search (#7)')" 'raised 1.2.3 1.3.0'

new_fixture package.json '{ "version": "1.2.3" }'
jq 'del(.versionFile)' "$repo/.claude/dev-workflow.json" >"$base/pf.json"
cp "$base/pf.json" "$repo/.claude/dev-workflow.json"
git -C "$repo" commit -q -am 'chore: no version file (#7)'
assert_contains "$(run 'feat: add search (#7)')" 'skip no-version-file'
assert_exit 0 test "$(commits_on_branch)" = 2

# --- Refused

# A title that isn't a Conventional Commit.
new_fixture VERSION 1.2.3
assert_exit 1 run 'Add search'
assert_exit 1 run 'feat add search'
assert_exit 0 test "$(commits_on_branch)" = 1

# The default branch moved on: bring it in first, so the version is worked out from what
# the merge will land on.
new_fixture VERSION 1.2.3
git -C "$repo" switch -q main
printf '1.3.0\n' >"$repo/VERSION"
git -C "$repo" commit -q -am 'chore: release 1.3.0 (#6)'
git -C "$repo" push -q origin main
git -C "$repo" switch -q feat/7-x
assert_exit 1 run 'feat: add search (#7)'
assert_contains "$(run 'feat: add search (#7)' 2>&1)" "origin/main"
git -C "$repo" merge -q --no-edit origin/main
assert_contains "$(run 'feat: add search (#7)')" 'raised 1.3.0 1.4.0'

# A hook that refuses the release commit leaves nothing behind: the file as it was, and
# nothing staged, so it can be run again.
new_fixture VERSION 1.2.3
mkdir "$base/hooks"
printf '#!/bin/sh\nexit 1\n' >"$base/hooks/pre-commit"
chmod +x "$base/hooks/pre-commit"
git -C "$repo" config core.hooksPath "$base/hooks"
assert_exit 1 run 'feat: add search (#7)'
assert_exit 0 test "$(cat "$repo/VERSION")" = 1.2.3
assert_exit 0 test -z "$(git -C "$repo" status --porcelain)"
assert_exit 0 test "$(commits_on_branch)" = 1
git -C "$repo" config --unset core.hooksPath

# Uncommitted changes would go into the release commit, or be lost.
new_fixture VERSION 1.2.3
printf 'x\n' >"$repo/other.txt"
git -C "$repo" add other.txt
assert_exit 1 run 'feat: add search (#7)'
assert_exit 0 test "$(commits_on_branch)" = 1

# On the default branch itself, there's no pull request to raise it in.
new_fixture VERSION 1.2.3
git -C "$repo" switch -q main
assert_exit 1 run 'feat: add search (#7)'

# --- The file is written in place, whatever its kind

# TOML: the [project] table's version, not another table's, nor a dependency's.
new_fixture pyproject.toml '[tool.other]
version = "1.2.3"

[project]  # the package
name = "app"
version = "1.2.3"

[project.optional-dependencies]
dev = ["x==1.2.3"]'
assert_contains "$(run 'feat: add search (#7)')" 'raised 1.2.3 1.3.0'
assert_contains "$(cat "$repo/pyproject.toml")" '[tool.other]
version = "1.2.3"'
assert_contains "$(cat "$repo/pyproject.toml")" 'name = "app"
version = "1.3.0"'
assert_exit 0 test "$(git -C "$repo" diff HEAD~1 --numstat -- pyproject.toml)" = "$(printf '1\t1\tpyproject.toml')"

new_fixture Cargo.toml "[package]
name = 'app'
version = '1.2.3'

[dependencies]
serde = { version = \"1.2.3\" }"
assert_contains "$(run 'fix: a bug (#7)')" 'raised 1.2.3 1.2.4'
assert_contains "$(cat "$repo/Cargo.toml")" "version = '1.2.4'"
assert_contains "$(cat "$repo/Cargo.toml")" 'serde = { version = "1.2.3" }'

# A plain file, in a subfolder.
new_fixture plugins/app/VERSION 1.2.3
assert_contains "$(run 'feat: add search (#7)')" 'raised 1.2.3 1.3.0'
assert_exit 0 test "$(cat "$repo/plugins/app/VERSION")" = 1.3.0

# The file's own form is kept: no final newline stays none, and Windows line endings and
# spaces around a plain version stay as they were.
new_fixture package.json '{ "version": "1.2.3" }'
printf '{\r\n  "version": "1.2.3"\r\n}' >"$repo/package.json"
git -C "$repo" commit -q -am 'chore: a file in another form (#7)'
git -C "$repo" push -q origin HEAD:main
assert_contains "$(run 'feat: add search (#7)')" 'raised 1.2.3 1.3.0'
printf '{\r\n  "version": "1.3.0"\r\n}' >"$base/expected.json"
assert_file_same "$repo/package.json" "$base/expected.json"

new_fixture VERSION 1.2.3
printf '  1.2.3 \r\nnotes\r\n' >"$repo/VERSION"
git -C "$repo" commit -q -am 'chore: a file in another form (#7)'
git -C "$repo" push -q origin HEAD:main
assert_contains "$(run 'fix: a bug (#7)')" 'raised 1.2.3 1.2.4'
printf '  1.2.4 \r\nnotes\r\n' >"$base/expected"
assert_file_same "$repo/VERSION" "$base/expected"

new_fixture pyproject.toml '[project]
version = "1.2.3"'
printf '[project]\nversion = "1.2.3"' >"$repo/pyproject.toml"
git -C "$repo" commit -q -am 'chore: no final newline (#7)'
git -C "$repo" push -q origin HEAD:main
assert_contains "$(run 'feat: add search (#7)')" 'raised 1.2.3 1.3.0'
printf '[project]\nversion = "1.3.0"' >"$base/expected.toml"
assert_file_same "$repo/pyproject.toml" "$base/expected.toml"

# JSON whose first "version" isn't the top-level one: refused, and left as it was, rather
# than changing the wrong one.
new_fixture package.json '{
  "engines": { "version": "1.2.3" },
  "version": "1.2.3"
}'
cp "$repo/package.json" "$base/before.json"
assert_exit 1 run 'feat: add search (#7)'
assert_file_same "$repo/package.json" "$base/before.json"
assert_exit 0 test "$(commits_on_branch)" = 1

# Compact JSON with a nested version first on the same line: the top-level one changes.
new_fixture package.json '{"meta":{"version":"0.1.0"},"version":"1.2.3"}'
assert_contains "$(run 'feat: add search (#7)')" 'raised 1.2.3 1.3.0'
printf '{"meta":{"version":"0.1.0"},"version":"1.3.0"}\n' >"$base/expected.json"
assert_file_same "$repo/package.json" "$base/expected.json"

# The file keeps its mode.
new_fixture VERSION 1.2.3
chmod 640 "$repo/VERSION"
run 'feat: add search (#7)' >/dev/null
assert_exit 0 test -n "$(find "$repo/VERSION" -perm 640)"

# A branch without an issue number still gets a Conventional Commit.
new_fixture VERSION 1.2.3 spike
assert_contains "$(run 'feat: add search')" 'raised 1.2.3 1.3.0'
assert_exit 0 test "$(head_subject)" = 'chore: release 1.3.0'

# --- Usage

assert_exit 2 sh "$RV"
assert_exit 2 sh "$RV" "$repo"
assert_exit 2 sh "$RV" "$(tmp_dir)/missing" 'feat: x'
