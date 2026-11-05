#!/bin/sh
# settings.sh plan|apply <root> [--allow-merge]: the attribution settings merged into
# .claude/settings.json, and with approval the gh pr merge permission in
# .claude/settings.local.json.

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
# shellcheck source=tests/lib/assert.sh
. "$ROOT/tests/lib/assert.sh"

SETTINGS="$ROOT/plugins/dev-workflow/scripts/setup/settings.sh"
work=$(tmp_dir)

run() { # <args...>: the JSON lines, failing unless exit 0
  _out=$(sh "$SETTINGS" "$@" 2>&1) || _assert_fail "settings.sh $* failed:
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

# --- no file: exactly the attribution form

r=$work/none
mkdir -p "$r"
out=$(run plan "$r")
assert_exit 0 test "$(action "$out" .claude/settings.json)" = create
assert_exit 1 test -e "$r/.claude"
out=$(run apply "$r")
printf '{\n  "attribution": {\n    "commit": "",\n    "pr": "",\n    "sessionUrl": false\n  }\n}\n' >"$work/exact"
assert_file_same "$r/.claude/settings.json" "$work/exact"
# Without approval the local file isn't touched.
assert_exit 1 test -e "$r/.claude/settings.local.json"
assert_exit 0 test -z "$(action "$out" .claude/settings.local.json)"

# A rerun is byte-identical.
cp "$r/.claude/settings.json" "$work/none-first"
out=$(run apply "$r")
assert_exit 0 test "$(action "$out" .claude/settings.json)" = keep
assert_file_same "$r/.claude/settings.json" "$work/none-first"

# --- other keys are kept, in their order, and so is the mode

r=$work/other
mkdir -p "$r/.claude"
printf '{"model": "x", "permissions": {"allow": ["Read"]}, "attribution": false}\n' >"$r/.claude/settings.json"
chmod 600 "$r/.claude/settings.json"
out=$(run apply "$r")
assert_exit 0 test "$(action "$out" .claude/settings.json)" = update
assert_exit 0 test "$(jq -c . "$r/.claude/settings.json")" = \
  '{"model":"x","permissions":{"allow":["Read"]},"attribution":{"commit":"","pr":"","sessionUrl":false}}'
# shellcheck disable=SC2012 # Only the mode is read.
assert_exit 0 test "$(ls -l "$r/.claude/settings.json" | cut -c 1-10)" = "-rw-------"
cp "$r/.claude/settings.json" "$work/other-first"
run apply "$r" >/dev/null
assert_file_same "$r/.claude/settings.json" "$work/other-first"

# Already right, in another layout: left as it is.
printf '{ "attribution": { "pr": "", "commit": "", "sessionUrl": false } }\n' >"$r/.claude/settings.json"
cp "$r/.claude/settings.json" "$work/other-layout"
out=$(run apply "$r")
assert_exit 0 test "$(action "$out" .claude/settings.json)" = keep
assert_file_same "$r/.claude/settings.json" "$work/other-layout"

# --- invalid JSON stops with an error and leaves the file alone

r=$work/broken
mkdir -p "$r/.claude"
printf '{ "model": \n' >"$r/.claude/settings.json"
cp "$r/.claude/settings.json" "$work/broken-first"
assert_exit 2 sh "$SETTINGS" apply "$r" --allow-merge
assert_file_same "$r/.claude/settings.json" "$work/broken-first"
assert_exit 1 test -e "$r/.claude/settings.local.json"
err=$(sh "$SETTINGS" apply "$r" 2>&1)
assert_contains "$err" ".claude/settings.json"
printf '[1]\n' >"$r/.claude/settings.json"
assert_exit 2 sh "$SETTINGS" apply "$r"

# --- the gh pr merge permission, only when approved, and never twice

r=$work/merge
mkdir -p "$r"
out=$(run apply "$r" --allow-merge)
assert_exit 0 test "$(action "$out" .claude/settings.local.json)" = create
assert_exit 0 test "$(jq -c . "$r/.claude/settings.local.json")" = '{"permissions":{"allow":["Bash(gh pr merge *)"]}}'
cp "$r/.claude/settings.local.json" "$work/merge-first"
out=$(run apply "$r" --allow-merge)
assert_exit 0 test "$(action "$out" .claude/settings.local.json)" = keep
assert_file_same "$r/.claude/settings.local.json" "$work/merge-first"

# An existing local file keeps its rules.
printf '{"permissions": {"allow": ["Bash(npm test)"], "deny": ["Read(.env)"]}, "env": {"A": "1"}}\n' >"$r/.claude/settings.local.json"
out=$(run apply "$r" --allow-merge)
assert_exit 0 test "$(action "$out" .claude/settings.local.json)" = update
assert_exit 0 test "$(jq -c . "$r/.claude/settings.local.json")" = \
  '{"permissions":{"allow":["Bash(npm test)","Bash(gh pr merge *)"],"deny":["Read(.env)"]},"env":{"A":"1"}}'

# A broken local file stops it too, before settings.json is written.
r=$work/merge-broken
mkdir -p "$r/.claude"
printf 'nope\n' >"$r/.claude/settings.local.json"
assert_exit 2 sh "$SETTINGS" apply "$r" --allow-merge
assert_exit 1 test -e "$r/.claude/settings.json"

# --- usage

assert_exit 2 sh "$SETTINGS"
assert_exit 2 sh "$SETTINGS" apply "$work/merge" --other
assert_exit 2 sh "$SETTINGS" apply "$work/missing"

# --- a .claude folder that leads out of the project is refused, before reading it

r=$work/escape
mkdir -p "$r" "$work/away"
printf '{"secret": "MARKER-7f3a"}\n' >"$work/away/settings.json"
cp "$work/away/settings.json" "$work/away-before"
ln -s "$work/away" "$r/.claude"
for m in plan apply; do
  assert_exit 2 sh "$SETTINGS" "$m" "$r" --allow-merge
  assert_contains "$(sh "$SETTINGS" "$m" "$r" 2>&1)" 'outside the project'
done
assert_file_same "$work/away/settings.json" "$work/away-before"
assert_exit 1 test -e "$work/away/settings.local.json"
