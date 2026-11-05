#!/bin/sh
# install-hooks.sh plan|apply <root> <templates>: copies the git hooks into .githooks/,
# keeps the ones the project edited, and turns them on the way the repo allows.

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
# shellcheck source=tests/lib/assert.sh
. "$ROOT/tests/lib/assert.sh"

INSTALL="$ROOT/plugins/dev-workflow/scripts/setup/install-hooks.sh"
LEDGER="$ROOT/plugins/dev-workflow/scripts/setup/ledger.sh"
TEMPLATES="$ROOT/plugins/dev-workflow/skills/setup/templates/githooks"
HOOKS="commit-msg pre-commit pre-push"
work=$(tmp_dir)

run() { # <plan|apply> <root> [templates]: the JSON lines, failing unless exit 0
  _out=$(sh "$INSTALL" "$1" "$2" "${3:-$TEMPLATES}" 2>&1) ||
    _assert_fail "install-hooks.sh $1 failed on $2:
$_out"
  printf '%s\n' "$_out" | jq -e -s 'length > 0 and all(.[]; (.path | type) == "string" and
    (.action | IN("create", "update", "keep", "conflict")))' >/dev/null ||
    _assert_fail "not one JSON line per path:
$_out"
  printf '%s\n' "$_out"
}

action() { # <json lines> <path>
  printf '%s\n' "$1" | jq -r --arg p "$2" 'select(.path == $p) | .action'
}

detail() { # <json lines> <path>
  printf '%s\n' "$1" | jq -r --arg p "$2" 'select(.path == $p) | .detail // ""'
}

hooks_path() { git -C "$1" config --local --get core.hooksPath; }

installed() { # <root>: every file is the template's, and each hook is executable
  for f in $HOOKS dw-lib.sh; do
    assert_file_same "$1/.githooks/$f" "$TEMPLATES/$f"
  done
  for f in $HOOKS; do
    assert_exit 0 test -x "$1/.githooks/$f"
  done
}

# --- no package.json: core.hooksPath, and plan writes nothing

r=$work/plain
new_repo "$r"
out=$(run plan "$r")
assert_exit 0 test "$(action "$out" .githooks/pre-commit)" = create
assert_exit 0 test "$(action "$out" core.hooksPath)" = update
assert_exit 1 test -e "$r/.githooks"
assert_exit 1 hooks_path "$r"
out=$(run apply "$r")
installed "$r"
assert_exit 0 test "$(hooks_path "$r")" = .githooks
assert_exit 0 test "$(sh "$LEDGER" get "$r/.claude/dev-workflow.json" .githooks/pre-push)" = \
  "$(sh "$LEDGER" hash "$TEMPLATES/pre-push")"

# A rerun keeps everything.
out=$(run apply "$r")
assert_exit 0 test "$(printf '%s\n' "$out" | jq -r .action | sort -u)" = keep

# A hook that lost its mode is made executable again.
chmod 644 "$r/.githooks/pre-push"
out=$(run apply "$r")
assert_exit 0 test "$(action "$out" .githooks/pre-push)" = update
assert_exit 0 test -x "$r/.githooks/pre-push"

# A path with spaces works too.
r="$work/a b/repo"
new_repo "$r"
printf '{ "scripts": {} }\n' >"$r/package.json"
run apply "$r" >/dev/null
installed "$r"
assert_exit 0 test "$(hooks_path "$r")" = .githooks

# --- templates from a plugin copy that lost its modes still install executable

r=$work/modes
new_repo "$r"
plain=$(tmp_dir)
cp "$TEMPLATES"/* "$plain/"
chmod 644 "$plain"/*
run apply "$r" "$plain" >/dev/null
installed "$r"

# --- an edited hook is left alone and reported; an untouched one is updated

r=$work/edited
new_repo "$r"
run apply "$r" >/dev/null
printf '# my change\n' >>"$r/.githooks/pre-commit"
cp "$r/.githooks/pre-commit" "$work/edited-hook"
newer=$(tmp_dir)
cp -p "$TEMPLATES"/* "$newer/"
printf '# newer\n' >>"$newer/pre-commit"
printf '# newer\n' >>"$newer/commit-msg"
out=$(run apply "$r" "$newer")
assert_exit 0 test "$(action "$out" .githooks/pre-commit)" = conflict
assert_contains "$(detail "$out" .githooks/pre-commit)" "# my change"
assert_file_same "$r/.githooks/pre-commit" "$work/edited-hook"
assert_exit 0 test "$(action "$out" .githooks/commit-msg)" = update
assert_file_same "$r/.githooks/commit-msg" "$newer/commit-msg"
assert_exit 0 test "$(action "$out" .githooks/pre-push)" = keep

# --- package.json: a prepare script, keeping the other scripts and the layout

r=$work/node
new_repo "$r"
printf '{\n\t"name": "x",\n\t"scripts": {\n\t\t"test": "node --test"\n\t}\n}\n' >"$r/package.json"
out=$(run apply "$r")
assert_exit 0 test "$(action "$out" package.json)" = update
assert_exit 0 test "$(jq -r .scripts.test "$r/package.json")" = "node --test"
assert_exit 0 test "$(jq -r .scripts.prepare "$r/package.json")" = "git config core.hooksPath .githooks || exit 0"
assert_exit 0 grep -q "$(printf '^\t\t"prepare"')" "$r/package.json"
assert_exit 0 test "$(hooks_path "$r")" = .githooks
installed "$r"
cp "$r/package.json" "$work/node-first"
out=$(run apply "$r")
assert_exit 0 test "$(action "$out" package.json)" = keep
assert_file_same "$r/package.json" "$work/node-first"

# An existing prepare keeps running first.
r=$work/node-prepare
new_repo "$r"
printf '{\n  "scripts": {\n    "prepare": "npm run build"\n  }\n}\n' >"$r/package.json"
run apply "$r" >/dev/null
assert_exit 0 test "$(jq -r .scripts.prepare "$r/package.json")" = \
  "npm run build && (git config core.hooksPath .githooks || exit 0)"
assert_exit 0 grep -q '^    "prepare"' "$r/package.json"
# No scripts at all.
r=$work/node-bare
new_repo "$r"
printf '{"name": "x"}\n' >"$r/package.json"
run apply "$r" >/dev/null
assert_exit 0 test "$(jq -c .scripts "$r/package.json")" = '{"prepare":"git config core.hooksPath .githooks || exit 0"}'

# --- husky: a call added in .husky/, keeping what's there

r=$work/husky
new_repo "$r"
mkdir -p "$r/.husky"
printf 'npx lint-staged\n' >"$r/.husky/pre-commit"
git -C "$r" config core.hooksPath .husky/_
out=$(run apply "$r")
assert_exit 0 test "$(action "$out" .husky/pre-commit)" = update
assert_exit 0 test "$(action "$out" .husky/pre-push)" = create
assert_exit 0 test "$(cat "$r/.husky/pre-commit")" = "$(printf 'npx lint-staged\n.githooks/pre-commit "$@"')"
assert_exit 0 grep -qx '.githooks/commit-msg "$@"' "$r/.husky/commit-msg"
assert_exit 0 test "$(hooks_path "$r")" = .husky/_
installed "$r"
cp "$r/.husky/pre-commit" "$work/husky-first"
out=$(run apply "$r")
assert_exit 0 test "$(action "$out" .husky/pre-commit)" = keep
assert_file_same "$r/.husky/pre-commit" "$work/husky-first"
# A hook file with no final newline still gets its own line.
printf 'npx x' >"$r/.husky/commit-msg"
run apply "$r" >/dev/null
assert_exit 0 test "$(cat "$r/.husky/commit-msg")" = "$(printf 'npx x\n.githooks/commit-msg "$@"')"

# --- lefthook: reported with the lines to add, and its config left alone

r=$work/lefthook
new_repo "$r"
printf 'pre-commit:\n  commands:\n    lint:\n      run: npx eslint\n' >"$r/lefthook.yml"
cp "$r/lefthook.yml" "$work/lefthook-first"
out=$(run apply "$r")
assert_exit 0 test "$(action "$out" lefthook.yml)" = conflict
assert_contains "$(detail "$out" lefthook.yml)" "run: .githooks/pre-commit"
assert_contains "$(detail "$out" lefthook.yml)" "run: .githooks/commit-msg {1}"
assert_contains "$(detail "$out" lefthook.yml)" "use_stdin: true"
assert_file_same "$r/lefthook.yml" "$work/lefthook-first"
assert_exit 1 hooks_path "$r"
installed "$r"
# Once the lines are in, it's kept.
# Only the lines are looked for, not where they sit.
detail "$out" lefthook.yml | sed -n '/^pre-commit:$/,$p' >>"$r/lefthook.yml"
out=$(run apply "$r")
assert_exit 0 test "$(action "$out" lefthook.yml)" = keep

# --- another core.hooksPath is never overwritten

r=$work/other-path
new_repo "$r"
git -C "$r" config core.hooksPath tools/hooks
out=$(run apply "$r")
assert_exit 0 test "$(action "$out" core.hooksPath)" = conflict
assert_contains "$(detail "$out" core.hooksPath)" 'tools/hooks/pre-commit'
assert_contains "$(detail "$out" core.hooksPath)" '.githooks/pre-commit "$@"'
assert_exit 0 test "$(hooks_path "$r")" = tools/hooks
installed "$r"

# --- usage

assert_exit 2 sh "$INSTALL"
assert_exit 2 sh "$INSTALL" apply "$work/plain"
assert_exit 2 sh "$INSTALL" apply "$work/missing" "$TEMPLATES"
assert_exit 2 sh "$INSTALL" apply "$work/plain" "$work/missing"
