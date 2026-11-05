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

# --- an import example inside a code fence moves with the text, and isn't removed

r=$work/fenced
mkdir -p "$r"
# shellcheck disable=SC2016 # Backticks are the fence, not a command.
printf '# Notes\n\nCLAUDE.md holds just this:\n\n```md\n@AGENTS.md\n```\n\n~~~\n@AGENTS.md\n~~~\n@AGENTS.md\n' >"$r/CLAUDE.md"
run apply "$r" >/dev/null
assert_file_same "$r/CLAUDE.md" "$work/import"
# shellcheck disable=SC2016 # Backticks are the fence, not a command.
printf '# Notes\n\nCLAUDE.md holds just this:\n\n```md\n@AGENTS.md\n```\n\n~~~\n@AGENTS.md\n~~~\n' >"$work/fenced-expected"
assert_file_same "$r/AGENTS.md" "$work/fenced-expected"

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

# The plan says so too, and writes nothing.
r=$work/link-plan
mkdir -p "$r"
printf '# Rules\n' >"$r/AGENTS.md"
cp "$r/AGENTS.md" "$work/link-plan-agents"
ln -s AGENTS.md "$r/CLAUDE.md"
out=$(run plan "$r")
assert_exit 0 test "$(action "$out" CLAUDE.md)" = update
assert_exit 0 test -z "$(action "$out" AGENTS.md)"
assert_exit 0 test -L "$r/CLAUDE.md"
assert_file_same "$r/AGENTS.md" "$work/link-plan-agents"

# An absolute link to it, or one through ./, is the same file.
r=$work/link-absolute
mkdir -p "$r"
printf '# Rules\n' >"$r/AGENTS.md"
ln -s "$r/AGENTS.md" "$r/CLAUDE.md"
out=$(run apply "$r")
assert_file_same "$r/CLAUDE.md" "$work/import"
assert_file_same "$r/AGENTS.md" "$work/link-plan-agents"
rm "$r/CLAUDE.md" && ln -s ./AGENTS.md "$r/CLAUDE.md"
out=$(run apply "$r")
assert_file_same "$r/CLAUDE.md" "$work/import"

# --- a symlink anywhere else is refused: nothing is read through it, or written

refused() { # <root> <mode>: exits 1 with one conflict line for CLAUDE.md, and says why
  if _out=$(sh "$CLAUDE_MD" "$2" "$1" 2>"$work/refused.err"); then _code=0; else _code=$?; fi
  [ "$_code" -eq 1 ] || _assert_fail "expected exit 1 from claude-md.sh $2 $1, got $_code:
$_out
$(cat "$work/refused.err")"
  assert_exit 0 test "$(printf '%s\n' "$_out" | jq -c '[.path, .action]')" = '["CLAUDE.md","conflict"]'
  assert_contains "$(printf '%s\n' "$_out" | jq -r .detail)" 'resolve it by hand'
  assert_contains "$(cat "$work/refused.err")" 'a link to somewhere other than AGENTS.md'
}

# Outside the repo: a private file is never copied into AGENTS.md.
outside=$work/outside
mkdir -p "$outside"
printf 'MARKER-PRIVATE-KEY-7f3a\n' >"$outside/id_secret"
cp "$outside/id_secret" "$work/outside-before"
r=$work/link-outside
mkdir -p "$r"
printf '# Rules\n' >"$r/AGENTS.md"
cp "$r/AGENTS.md" "$work/link-outside-agents"
ln -s "$outside/id_secret" "$r/CLAUDE.md"
for m in plan apply; do
  refused "$r" "$m"
  assert_file_same "$r/AGENTS.md" "$work/link-outside-agents"
  assert_not_contains "$(cat "$r/AGENTS.md")" MARKER-PRIVATE-KEY
  assert_exit 0 test -L "$r/CLAUDE.md"
  assert_file_same "$outside/id_secret" "$work/outside-before"
done
assert_not_contains "$(cat "$work/refused.err")" MARKER-PRIVATE-KEY
# With no AGENTS.md, none is made.
rm "$r/AGENTS.md"
refused "$r" apply
assert_exit 1 test -e "$r/AGENTS.md"
# A relative link out of the repo is no different.
rm "$r/CLAUDE.md" && ln -s ../outside/id_secret "$r/CLAUDE.md"
refused "$r" apply
assert_exit 1 test -e "$r/AGENTS.md"

# Another file in the repo, a dangling link, and a chain of two links to AGENTS.md.
r=$work/link-other
mkdir -p "$r/docs"
printf 'Other rules\n' >"$r/docs/rules.md"
cp "$r/docs/rules.md" "$work/link-other-rules"
printf '# Rules\n' >"$r/AGENTS.md"
ln -s docs/rules.md "$r/CLAUDE.md"
refused "$r" apply
assert_exit 0 test -L "$r/CLAUDE.md"
assert_file_same "$r/AGENTS.md" "$work/link-plan-agents"
assert_file_same "$r/docs/rules.md" "$work/link-other-rules"
rm "$r/CLAUDE.md" && ln -s missing.md "$r/CLAUDE.md"
refused "$r" apply
assert_exit 0 test -L "$r/CLAUDE.md"
assert_exit 1 test -e "$r/missing.md"
rm "$r/CLAUDE.md" && ln -s AGENTS.md "$r/middle.md" && ln -s middle.md "$r/CLAUDE.md"
refused "$r" apply
assert_exit 0 test -L "$r/CLAUDE.md"
assert_file_same "$r/AGENTS.md" "$work/link-plan-agents"
# A link to AGENTS.md with no AGENTS.md there dangles.
r=$work/link-dangling-agents
mkdir -p "$r"
ln -s AGENTS.md "$r/CLAUDE.md"
refused "$r" apply
assert_exit 1 test -e "$r/AGENTS.md"

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
