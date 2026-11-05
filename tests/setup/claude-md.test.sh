#!/bin/sh
# claude-md.sh plan|apply <root>: CLAUDE.md becomes exactly the import @AGENTS.md,
# and any text of its own moves into AGENTS.md first, so nothing is lost.

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
# shellcheck source=tests/lib/assert.sh
. "$ROOT/tests/lib/assert.sh"

CLAUDE_MD="$ROOT/plugins/dev-workflow/scripts/setup/claude-md.sh"
LEGACY="$ROOT/plugins/dev-workflow/skills/setup/references/legacy"
work=$(tmp_dir)
printf '@AGENTS.md\n' >"$work/import"

run() { # <plan|apply> <root>: the JSON lines, failing unless exit 0
  _out=$(sh "$CLAUDE_MD" "$1" "$2" 2>&1) || _assert_fail "claude-md.sh $1 failed on $2:
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

# --- absent: the import, and plan writes nothing

r=$work/absent
mkdir -p "$r"
out=$(run plan "$r")
assert_exit 0 test "$(action "$out" CLAUDE.md)" = create
assert_exit 1 test -e "$r/CLAUDE.md"
out=$(run apply "$r")
assert_file_same "$r/CLAUDE.md" "$work/import"
assert_exit 1 test -e "$r/AGENTS.md"

# A rerun changes nothing.
out=$(run apply "$r")
assert_exit 0 test "$(action "$out" CLAUDE.md)" = keep
assert_file_same "$r/CLAUDE.md" "$work/import"

# --- an old pointer becomes the import

r=$work/pointer
mkdir -p "$r"
cp "$LEGACY/pointer-fd04f50.md" "$r/CLAUDE.md"
printf '# Rules\n' >"$r/AGENTS.md"
cp "$r/AGENTS.md" "$work/pointer-agents"
out=$(run apply "$r")
assert_exit 0 test "$(action "$out" CLAUDE.md)" = update
assert_file_same "$r/CLAUDE.md" "$work/import"
assert_file_same "$r/AGENTS.md" "$work/pointer-agents"

# The import with CRLF is rewritten to the exact bytes.
printf '@AGENTS.md\r\n' >"$r/CLAUDE.md"
out=$(run apply "$r")
assert_exit 0 test "$(action "$out" CLAUDE.md)" = update
assert_file_same "$r/CLAUDE.md" "$work/import"

# --- content moves into AGENTS.md first, and nothing is lost

r=$work/content
mkdir -p "$r"
printf '# Rules\n\nKeep it small.' >"$r/AGENTS.md"
printf '# Notes\n\nUse tabs, and "quotes".\n@AGENTS.md\n' >"$r/CLAUDE.md"
out=$(run plan "$r")
assert_exit 0 test "$(action "$out" AGENTS.md)" = update
assert_exit 0 test "$(action "$out" CLAUDE.md)" = update
assert_exit 0 test "$(cat "$r/AGENTS.md")" = "$(printf '# Rules\n\nKeep it small.')"
out=$(run apply "$r")
assert_file_same "$r/CLAUDE.md" "$work/import"
printf '# Rules\n\nKeep it small.\n\n# Notes\n\nUse tabs, and "quotes".\n' >"$work/content-expected"
assert_file_same "$r/AGENTS.md" "$work/content-expected"
out=$(run apply "$r")
assert_exit 0 test "$(action "$out" CLAUDE.md)" = keep
assert_exit 0 test -z "$(action "$out" AGENTS.md)"
assert_file_same "$r/AGENTS.md" "$work/content-expected"

# With no AGENTS.md, the text makes one.
r=$work/content-new
mkdir -p "$r"
printf 'Line one\n\nLine two\n' >"$r/CLAUDE.md"
cp "$r/CLAUDE.md" "$work/content-new-expected"
out=$(run apply "$r")
assert_exit 0 test "$(action "$out" AGENTS.md)" = create
assert_file_same "$r/AGENTS.md" "$work/content-new-expected"
assert_file_same "$r/CLAUDE.md" "$work/import"

# --- a symlink to AGENTS.md becomes a regular file, and AGENTS.md keeps its bytes

r=$work/link
mkdir -p "$r"
printf '# Rules\n\nAll here.\n' >"$r/AGENTS.md"
cp "$r/AGENTS.md" "$work/link-agents"
ln -s AGENTS.md "$r/CLAUDE.md"
out=$(run apply "$r")
assert_exit 0 test "$(action "$out" CLAUDE.md)" = update
assert_exit 1 test -L "$r/CLAUDE.md"
assert_file_same "$r/CLAUDE.md" "$work/import"
assert_file_same "$r/AGENTS.md" "$work/link-agents"

# A symlink to another file: its text moves, and the file it pointed to stays.
r=$work/link-other
mkdir -p "$r/docs"
printf 'Other rules\n' >"$r/docs/rules.md"
cp "$r/docs/rules.md" "$work/link-other-rules"
ln -s docs/rules.md "$r/CLAUDE.md"
out=$(run apply "$r")
assert_exit 1 test -L "$r/CLAUDE.md"
assert_file_same "$r/CLAUDE.md" "$work/import"
assert_file_same "$r/AGENTS.md" "$work/link-other-rules"
assert_file_same "$r/docs/rules.md" "$work/link-other-rules"

# --- AGENTS.md as a symlink is refused, before anything is written

r=$work/agents-link
mkdir -p "$r"
printf 'Mine\n' >"$r/real.md"
ln -s real.md "$r/AGENTS.md"
printf 'Notes\n' >"$r/CLAUDE.md"
assert_exit 2 sh "$CLAUDE_MD" apply "$r"
assert_exit 0 test "$(cat "$r/CLAUDE.md")" = Notes
assert_exit 0 test "$(cat "$r/real.md")" = Mine

# --- usage

assert_exit 2 sh "$CLAUDE_MD"
assert_exit 2 sh "$CLAUDE_MD" write "$work/absent"
assert_exit 2 sh "$CLAUDE_MD" apply "$work/missing"
