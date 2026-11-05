#!/bin/sh
# The old texts setup recognises: every rule block and CLAUDE.md pointer this repo
# ever published, read from git history so it keeps working after the old files are
# deleted. Also tests the helpers in scripts/setup/legacy.sh that compare against them.

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
# shellcheck source=tests/lib/assert.sh
. "$ROOT/tests/lib/assert.sh"

LEGACY_DIR="$ROOT/plugins/dev-workflow/skills/setup/references/legacy"
# shellcheck source=plugins/dev-workflow/scripts/setup/legacy.sh
. "$ROOT/plugins/dev-workflow/scripts/setup/legacy.sh"

work=$(tmp_dir)
used="$work/used"
: >"$used"

skill=plugins/web-dev-workflow/skills/setup/SKILL.md
issues=plugins/dev-workflow/commands/enable-github-issues.md

# --- history: which commits published a text

git -C "$ROOT" log --format=%H -- "$skill" "$issues" >"$work/commits" ||
  _assert_fail "could not read the history of $skill and $issues"
# A shallow clone would quietly check fewer commits.
for known in de3a6b4 f4694d3 17416e9 fd04f50; do
  full=$(git -C "$ROOT" rev-parse --verify -q "$known^{commit}") ||
    _assert_fail "commit $known is missing: this test needs the full history"
  assert_exit 0 grep -qx "$full" "$work/commits"
done

# fences <commit> <path> <out-prefix>: writes each ```markdown fence in the file at
# that commit to <out-prefix>.<n>, without the fence's own indentation.
fences() {
  git -C "$ROOT" show "$1:$2" >"$work/file" || _assert_fail "could not read $2 at $1"
  awk -v out="$3" '
    !fenced && /^ *```markdown$/ { fenced = 1; n++; indent = index($0, "`") - 1; next }
    fenced && /^ *```$/ { fenced = 0; close(out "." n); next }
    fenced { print substr($0, indent + 1) > (out "." n) }
  ' "$work/file"
}

# check_web <fence> <commit>: the block is the web-N files joined by blank lines.
check_web() {
  sections=$(grep -c '^### ' "$1")
  expected="$work/expected"
  : >"$expected"
  first=1
  for part in "$LEGACY_DIR/web-$sections".*.md; do
    [ -f "$part" ] || _assert_fail "no legacy files for web-$sections, published at $2"
    [ "$first" -eq 1 ] || printf '\n' >>"$expected"
    first=0
    cat "$part" >>"$expected"
    printf '%s\n' "${part##*/}" >>"$used"
  done
  assert_file_same "$1" "$expected"
}

# check_one <fence> <commit> <glob>: the fence is byte for byte one of the files.
check_one() {
  for candidate in "$LEGACY_DIR"/$3; do
    if cmp -s "$1" "$candidate"; then
      printf '%s\n' "${candidate##*/}" >>"$used"
      return 0
    fi
  done
  _assert_fail "text published at $2 is not in legacy/ as $3:
$(cat "$1")"
}

pointers_seen=0
while IFS= read -r commit; do
  for path in "$skill" "$issues"; do
    # A commit that deleted or never had the file published nothing in it.
    git -C "$ROOT" cat-file -e "$commit:$path" 2>/dev/null || continue
    rm -f "$work/fence".*
    fences "$commit" "$path" "$work/fence"
    for fence in "$work/fence".*; do
      [ -f "$fence" ] || continue
      case $(head -n 1 "$fence") in
        '## Web Dev Workflow Rules') check_web "$fence" "$commit" ;;
        '## GitHub Issue-Driven Workflow') check_one "$fence" "$commit" 'issues.md' ;;
        '# CLAUDE.md')
          check_one "$fence" "$commit" 'pointer-*.md'
          pointers_seen=$((pointers_seen + 1))
          ;;
        *) _assert_fail "unknown fenced text in $path at $commit: $(head -n 1 "$fence")" ;;
      esac
    done
  done
done <"$work/commits"
assert_exit 0 test "$pointers_seen" -gt 0

# Before the pointer, the rules went straight into CLAUDE.md: no pointer to find.
for commit in de3a6b4 f4694d3 17416e9; do
  rm -f "$work/fence".*
  for path in "$skill" "$issues"; do
    git -C "$ROOT" cat-file -e "$commit:$path" 2>/dev/null || continue
    fences "$commit" "$path" "$work/fence.$commit"
  done
  for fence in "$work/fence.$commit".*; do
    [ -f "$fence" ] || continue
    assert_exit 1 grep -qx '# CLAUDE.md' "$fence"
  done
done

# The setup command only ever pointed at the skill: it published no text of its own.
git -C "$ROOT" log --format=%H -- plugins/web-dev-workflow/commands/setup.md >"$work/setup-commits"
assert_exit 0 test -s "$work/setup-commits"
while IFS= read -r commit; do
  git -C "$ROOT" cat-file -e "$commit:plugins/web-dev-workflow/commands/setup.md" 2>/dev/null || continue
  git -C "$ROOT" show "$commit:plugins/web-dev-workflow/commands/setup.md" >"$work/setup.md"
  assert_exit 1 grep -q '```' "$work/setup.md"
done <"$work/setup-commits"

# --- legacy/ holds those texts and nothing else

for file in "$LEGACY_DIR"/*; do
  assert_exit 0 grep -qx "${file##*/}" "$used"
done
# Both versions exist, and the five subsections they share are the same text.
assert_exit 0 test "$(find "$LEGACY_DIR" -name 'web-5.*.md' | wc -l)" -eq 6
assert_exit 0 test "$(find "$LEGACY_DIR" -name 'web-6.*.md' | wc -l)" -eq 7
for part in "$LEGACY_DIR"/web-5.*.md; do
  assert_file_same "$part" "$LEGACY_DIR/web-6.${part##*/web-5.}"
done
assert_exit 0 test -f "$LEGACY_DIR/web-6.6-commit-discipline.md"

# --- legacy_normalise

printf 'a  \r\nb\t\r\n\r\n  \n' >"$work/messy"
assert_exit 0 test "$(legacy_normalise <"$work/messy" | od -c | tr -s ' ')" = "$(printf 'a\nb\n' | od -c | tr -s ' ')"
# Leading blank lines and indentation are text, not trailing whitespace.
printf '\n  a\n' >"$work/leading"
assert_exit 0 test "$(legacy_normalise <"$work/leading" | od -c | tr -s ' ')" = "$(printf '\n  a\n' | od -c | tr -s ' ')"

# --- legacy_match_block

section="$LEGACY_DIR/web-6.6-commit-discipline.md"

out=$(legacy_match_block "$section")
assert_exit 0 test "$out" = "web-6.6-commit-discipline"

# A subsection both versions share names both files.
out=$(legacy_match_block "$LEGACY_DIR/web-5.1-conventional-commits.md")
assert_exit 0 test "$out" = "web-5.1-conventional-commits
web-6.1-conventional-commits"

# CRLF, trailing spaces, no final newline and trailing blank lines still match.
sed 's/$/  \r/' "$section" >"$work/crlf"
printf '\r\n\r\n' >>"$work/crlf"
assert_exit 0 legacy_match_block "$work/crlf"
printf '%s' "$(cat "$section")" >"$work/no-newline"
assert_exit 0 legacy_match_block "$work/no-newline"

# Any other change is an edit.
sed 's/timely/prompt/' "$section" >"$work/edited"
assert_exit 1 legacy_match_block "$work/edited"
sed 's/^/ /' "$section" >"$work/indented"
assert_exit 1 legacy_match_block "$work/indented"
printf '\n' >"$work/blank-first"
cat "$section" >>"$work/blank-first"
assert_exit 1 legacy_match_block "$work/blank-first"
: >"$work/empty"
assert_exit 1 legacy_match_block "$work/empty"
out=$(legacy_match_block "$work/edited")
assert_exit 0 test -z "$out"

# The heading, the issues block and the pointer are texts too.
printf '## Web Dev Workflow Rules\n' >"$work/heading"
assert_contains "$(legacy_match_block "$work/heading")" "web-6.0-heading"
assert_exit 0 test "$(legacy_match_block "$LEGACY_DIR/issues.md")" = "issues"
printf '# CLAUDE.md\r\n\r\nThe canonical agent instructions for this project live in [AGENTS.md](./AGENTS.md).\r\n' >"$work/pointer"
assert_contains "$(legacy_match_block "$work/pointer")" "pointer-"

# Unreadable input and a missing legacy folder are errors, never "edited".
assert_exit 2 legacy_match_block "$work/missing"
assert_exit 2 legacy_match_block "$work"
# shellcheck disable=SC2016 # Expanded by the inner shell.
assert_exit 2 sh -c '
  LEGACY_DIR=$2
  . "$1/plugins/dev-workflow/scripts/setup/legacy.sh"
  legacy_match_block "$3"
' sh "$ROOT" "$work/no-such-dir" "$section"

# --- legacy_blocks_in

block() { # <version>: the whole published block
  first=1
  for part in "$LEGACY_DIR/web-$1".*.md; do
    [ "$first" -eq 1 ] || printf '\n'
    first=0
    cat "$part"
  done
}

blocks_of() { # <file>: the ids, space-separated
  legacy_blocks_in "$1" | tr '\n' ' ' | sed 's/ $//'
}

f="$work/agents"

{ printf '# Project\n\nOwn text.\n\n'; block 5; } >"$f"
assert_exit 0 test "$(blocks_of "$f")" = "web-5"

{ block 6; printf '\n'; cat "$LEGACY_DIR/issues.md"; } >"$f"
assert_exit 0 test "$(blocks_of "$f")" = "web-6 issues"

# CRLF and trailing spaces don't hide a block.
block 6 | sed 's/$/ \r/' >"$f"
assert_exit 0 test "$(blocks_of "$f")" = "web-6"

# An edited subsection still leaves the block there to upgrade.
block 6 | sed 's/timely/prompt/; s/Serena (MCP plugin)/Serena/' >"$f"
assert_exit 0 test "$(blocks_of "$f")" = "web-6"
block 5 | sed 's/Serena (MCP plugin)/Serena/' >"$f"
assert_exit 0 test "$(blocks_of "$f")" = "web-5"
sed 's/timely/prompt/' "$LEGACY_DIR/issues.md" >"$f"
assert_exit 0 test "$(blocks_of "$f")" = "issues"

# The old skill appended a missing subsection at the end, after other sections.
{ block 5; printf '\n## Own rules\n\nText.\n\n'; cat "$section"; } >"$f"
assert_exit 0 test "$(blocks_of "$f")" = "web-6"

# Published subsections without their heading are still found.
cat "$LEGACY_DIR/web-5.2-test-driven-development.md" >"$f"
assert_exit 0 test "$(blocks_of "$f")" = "web-5"

# A project's own section of the same name, under its own heading, isn't the block.
{ block 5; printf '\n## Own rules\n\n### Commit Discipline\nOur own text.\n'; } >"$f"
assert_exit 0 test "$(blocks_of "$f")" = "web-5"
printf '## Own rules\n\n### Commit Discipline\nOur own text.\n' >"$f"
assert_exit 0 test -z "$(blocks_of "$f")"

# Text quoted in a code fence isn't a block, and its lines don't end a section.
{ printf '# Docs\n\n```markdown\n'; block 6; printf '```\n'; } >"$f"
assert_exit 0 test -z "$(blocks_of "$f")"

printf '# Project\n\nNothing old here.\n' >"$f"
assert_exit 0 test -z "$(blocks_of "$f")"
: >"$f"
assert_exit 0 test -z "$(blocks_of "$f")"
assert_exit 2 legacy_blocks_in "$work/missing"
