#!/bin/sh
# ledger.sh: the fingerprints of what setup wrote, kept in the project file's
# "managed" object, and the atomic write it uses.

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
# shellcheck source=tests/lib/assert.sh
. "$ROOT/tests/lib/assert.sh"

LEDGER="$ROOT/plugins/dev-workflow/scripts/setup/ledger.sh"
work=$(tmp_dir)
pf="$work/repo/.claude/dev-workflow.json"

# --- hash: git's blob hash, the same outside a repo

printf 'some text\n' >"$work/a"
assert_exit 0 test "$(sh "$LEDGER" hash "$work/a")" = "$(git hash-object --no-filters "$work/a")"
assert_exit 0 test "$(cd "$work" && sh "$LEDGER" hash a)" = "$(git hash-object --no-filters "$work/a")"
assert_exit 2 sh "$LEDGER" hash "$work/missing"

# --- get and set

# No project file yet: nothing recorded.
assert_exit 1 sh "$LEDGER" get "$pf" "AGENTS.md#workflow"
# set creates the file and its folder.
assert_exit 0 sh "$LEDGER" set "$pf" "AGENTS.md#workflow" abc123
assert_exit 0 test "$(sh "$LEDGER" get "$pf" "AGENTS.md#workflow")" = "abc123"
assert_exit 1 sh "$LEDGER" get "$pf" "AGENTS.md#tools"

# Other keys and fields survive, and the file's mode is kept.
printf '{\n  "schemaVersion": 1,\n  "commands": { "check": "make check" },\n  "managed": { ".githooks/pre-push": "f00" }\n}\n' >"$pf"
chmod 640 "$pf"
assert_exit 0 sh "$LEDGER" set "$pf" "AGENTS.md#tools" "d00d"
assert_exit 0 test "$(jq -c . "$pf")" = '{"schemaVersion":1,"commands":{"check":"make check"},"managed":{".githooks/pre-push":"f00","AGENTS.md#tools":"d00d"}}'
# shellcheck disable=SC2012 # Only the mode is read.
assert_exit 0 test "$(ls -l "$pf" | cut -c 1-10)" = "-rw-r-----"
# Overwrites its own key.
assert_exit 0 sh "$LEDGER" set "$pf" "AGENTS.md#tools" "beef"
assert_exit 0 test "$(sh "$LEDGER" get "$pf" "AGENTS.md#tools")" = "beef"
# No temp file is left beside it.
assert_exit 0 test "$(find "$work/repo/.claude" -type f | wc -l)" -eq 1

# A key holding quotes or a dot is just a key.
assert_exit 0 sh "$LEDGER" set "$pf" 'a "b".c' "1"
assert_exit 0 test "$(sh "$LEDGER" get "$pf" 'a "b".c')" = "1"

# Broken JSON is an error, and the file is left alone.
printf '{ broken\n' >"$pf"
cp "$pf" "$work/broken"
assert_exit 2 sh "$LEDGER" get "$pf" "AGENTS.md#tools"
assert_exit 2 sh "$LEDGER" set "$pf" "AGENTS.md#tools" "beef"
assert_file_same "$pf" "$work/broken"
# A file that isn't an object, or a managed that isn't one, is broken too.
printf '[1]\n' >"$pf"
assert_exit 2 sh "$LEDGER" set "$pf" "k" "v"
printf '{"managed":"x"}\n' >"$pf"
assert_exit 2 sh "$LEDGER" get "$pf" "k"

# --- usage

assert_exit 2 sh "$LEDGER"
assert_exit 2 sh "$LEDGER" get "$pf"
assert_exit 2 sh "$LEDGER" set "$pf" "k"
assert_exit 2 sh "$LEDGER" frob "$pf" "k"

# --- atomic_write keeps the mode, or uses the umask for a new file

# shellcheck source=plugins/dev-workflow/scripts/setup/atomic.sh
. "$ROOT/plugins/dev-workflow/scripts/setup/atomic.sh"
printf 'old\n' >"$work/script"
chmod 755 "$work/script"
printf 'new\n' | atomic_write "$work/script"
assert_exit 0 test "$(cat "$work/script")" = "new"
# shellcheck disable=SC2012 # Only the mode is read.
assert_exit 0 test "$(ls -l "$work/script" | cut -c 1-10)" = "-rwxr-xr-x"
(umask 027 && printf 'x\n' | atomic_write "$work/fresh")
# shellcheck disable=SC2012 # Only the mode is read.
assert_exit 0 test "$(ls -l "$work/fresh" | cut -c 1-10)" = "-rw-r-----"
# A symlink isn't written through or replaced.
ln -s script "$work/link"
# shellcheck disable=SC2016 # Expanded by the inner shell.
assert_exit 2 sh -c '. "$1"; printf "y\n" | atomic_write "$2"' sh \
  "$ROOT/plugins/dev-workflow/scripts/setup/atomic.sh" "$work/link"
assert_exit 0 test -L "$work/link"
assert_exit 0 test "$(cat "$work/script")" = "new"
assert_exit 0 test "$(find "$work" -name '.dw-write.*' | wc -l)" -eq 0
