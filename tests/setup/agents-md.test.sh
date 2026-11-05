#!/bin/sh
# agents-md.sh plan|apply <root> <templates>: writes AGENTS.md's managed sections,
# updates the ones the project left alone, keeps the ones it edited, and replaces
# the old rule blocks. Every case runs in temp folders.

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
# shellcheck source=tests/lib/assert.sh
. "$ROOT/tests/lib/assert.sh"
# shellcheck source=tests/lib/markdown.sh
. "$ROOT/tests/lib/markdown.sh"

AGENTS_MD="$ROOT/plugins/dev-workflow/scripts/setup/agents-md.sh"
TEMPLATES="$ROOT/plugins/dev-workflow/skills/setup/templates/agents"
LEGACY="$ROOT/plugins/dev-workflow/skills/setup/references/legacy"
SECTIONS="decisions workflow testing tools models communication"

md() { # <plan|apply> <root> [templates]: the JSON lines, failing unless exit 0
  _out=$(sh "$AGENTS_MD" "$1" "$2" "${3:-$TEMPLATES}" 2>&1) ||
    _assert_fail "agents-md.sh $1 failed on $2:
$_out"
  printf '%s\n' "$_out" | jq -e -s 'all(.[]; (.section | type) == "string" and
    (.action | IN("create", "update", "keep", "conflict")))' >/dev/null ||
    _assert_fail "not one JSON line per section:
$_out"
  printf '%s\n' "$_out"
}

action() { # <json lines> <section>: that section's action
  printf '%s\n' "$1" | jq -r --arg s "$2" 'select(.section == $s) | .action'
}

field() { # <json lines> <section> <field>
  printf '%s\n' "$1" | jq -r --arg s "$2" --arg f "$3" 'select(.section == $s) | .[$f] // empty'
}

assert_actions() { # <json lines> <expected "section:action ..."> in that order
  _got=$(printf '%s\n' "$1" | jq -r '"\(.section):\(.action)"' | tr '\n' ' ' | sed 's/ $//')
  [ "$_got" = "$2" ] || _assert_fail "expected actions: $2
got: $_got"
}

all_actions() { # <action> [project action]: every section with that action
  _list="project:${2:-keep}"
  for _s in $SECTIONS; do _list="$_list $_s:$1"; done
  printf '%s' "$_list"
}

ledger_of() { # <root> <section>
  jq -r --arg k "AGENTS.md#$2" '.managed[$k] // empty' "$1/.claude/dev-workflow.json"
}

text_hash() { # <file>: the fingerprint of its text with the comparison rule applied
  awk -f "$ROOT/plugins/dev-workflow/scripts/setup/agents-normalise.awk" "$1" | git hash-object --no-filters --stdin
}

outside() { # <file>: its lines outside managed sections, markers included
  awk '/^<!-- dev-workflow:end / { inside = 0 } !inside { print }
    /^<!-- dev-workflow:begin / { inside = 1 }' "$1"
}

block() { # <version>: a whole published web block
  first=1
  for part in "$LEGACY/web-$1".*.md; do
    [ "$first" -eq 1 ] || printf '\n'
    first=0
    cat "$part"
  done
}

snapshot() { # <root> <name>: copies AGENTS.md and the project file aside
  cp "$1/AGENTS.md" "$work/$2.agents"
  cp "$1/.claude/dev-workflow.json" "$work/$2.json"
}

assert_unchanged() { # <root> <name>
  assert_file_same "$1/AGENTS.md" "$work/$2.agents"
  assert_file_same "$1/.claude/dev-workflow.json" "$work/$2.json"
}

work=$(tmp_dir)

# --- a new file: every section, in order, under 200 lines once filled in

r="$work/new"
mkdir -p "$r"
out=$(md plan "$r")
assert_actions "$out" "$(all_actions create create)"
# A plan writes nothing.
assert_exit 0 test "$(find "$r" | wc -l)" -eq 1

out=$(md apply "$r")
assert_actions "$out" "$(all_actions create create)"
assert_exit 0 test -z "$(printf '%s\n' "$out" | jq -r '.diff // empty')"

grep -E '^#{1,2} ' "$r/AGENTS.md" >"$work/headings"
printf '%s\n' '# Project' '## Stack' '## Commands' '## Glossary' '## Code organisation' \
  '## Decisions' '## Workflow' '## Testing' '## Tools' '## Models' '## Communication' >"$work/expected"
assert_file_same "$work/headings" "$work/expected"

# In the form Prettier keeps, so a project checking its files with it passes.
assert_markdown_form "$r/AGENTS.md"
for s in $SECTIONS; do
  # Each section sits between its markers, as its template's text, with a blank line
  # either side, as Prettier puts between blocks.
  awk -v s="$s" '$0 == "<!-- dev-workflow:end " s " -->" { inside = 0 }
    inside { print } $0 == "<!-- dev-workflow:begin " s " -->" { inside = 1 }' \
    "$r/AGENTS.md" >"$work/body"
  { echo && cat "$TEMPLATES/$s.md" && echo; } >"$work/expected-body"
  assert_file_same "$work/body" "$work/expected-body"
  assert_exit 0 test "$(ledger_of "$r" "$s")" = "$(text_hash "$TEMPLATES/$s.md")"
done
# The project part is the template, untouched and outside any markers.
head -n "$(wc -l <"$TEMPLATES/project.md")" "$r/AGENTS.md" >"$work/head"
assert_file_same "$work/head" "$TEMPLATES/project.md"
# No blank line at the end, and none doubled.
assert_exit 0 test -n "$(tail -n 1 "$r/AGENTS.md")"
assert_exit 0 test "$(awk 'prev == "" && $0 == "" { n++ } { prev = $0 } END { print n + 0 }' "$r/AGENTS.md")" -eq 0

# Filled in with a full page of sample text per prompt, it stays under 200 lines.
awk '/_Fill in: / { for (i = 1; i <= 10; i++) print "- Sample line " i " of the owner'"'"'s own text."; next }
  { print }' "$r/AGENTS.md" >"$work/filled"
assert_exit 0 test "$(grep -c 'Fill in' "$work/filled")" -eq 0
lines=$(wc -l <"$work/filled")
[ "$lines" -lt 200 ] || _assert_fail "filled AGENTS.md has $lines lines, over 200"

# --- a rerun changes nothing

snapshot "$r" first
out=$(md apply "$r")
assert_actions "$out" "$(all_actions keep)"
assert_unchanged "$r" first

# Formatting alone isn't an edit: another list marker, table padding, and blank lines
# added or taken away, as Prettier or a person might change them.
ft="$work/templates-table"
cp -R "$TEMPLATES" "$ft"
printf '\n| Key | What        |\n| --- | ----------- |\n| a   | the first   |\n| b   | the second  |\n' >>"$ft/models.md"
fr="$work/formatted"
mkdir -p "$fr"
md apply "$fr" "$ft" >/dev/null
assert_markdown_form "$fr/AGENTS.md"
awk '
  /^<!-- dev-workflow:begin / { print; inside = 1; skip_blank = 1; next }
  /^<!-- dev-workflow:end / { inside = 0 }
  inside && skip_blank && $0 == "" { skip_blank = 0; next }
  inside && /^- / { sub(/^- /, "*   ") }
  inside && /^\| / { gsub(/ +\|/, "|"); gsub(/\| +/, "|"); if (/^[-|]+$/) gsub(/-+/, "--") }
  inside && /^## / { print; print ""; print ""; next }
  { print }
' "$fr/AGENTS.md" >"$work/formatted.md"
assert_contains "$(cat "$work/formatted.md")" '*   Always tell the owner'
assert_contains "$(cat "$work/formatted.md")" '|a|the first|'
cp "$work/formatted.md" "$fr/AGENTS.md"
snapshot "$fr" formatted
out=$(md apply "$fr" "$ft")
assert_actions "$out" "$(all_actions keep)"
assert_unchanged "$fr" formatted
# Then, with a newer template, each is updated as one setup wrote.
printf -- '- One more rule.\n' >>"$ft/communication.md"
out=$(md apply "$fr" "$ft")
assert_exit 0 test "$(action "$out" communication)" = update
assert_exit 0 test "$(action "$out" models)" = keep
assert_contains "$(cat "$fr/AGENTS.md")" '- One more rule.'
# A real edit still counts.
sed 's/the second/the other/' "$fr/AGENTS.md" >"$work/formatted.md" && cp "$work/formatted.md" "$fr/AGENTS.md"
printf -- '- A newer models rule.\n' >>"$ft/models.md"
out=$(md apply "$fr" "$ft")
assert_exit 0 test "$(action "$out" models)" = conflict
assert_contains "$(field "$out" models diff)" '+|b|the other|'

# Filling in the project's prompts is the project's business.
cp "$work/filled" "$r/AGENTS.md"
snapshot "$r" filled
out=$(md apply "$r")
assert_actions "$out" "$(all_actions keep)"
assert_unchanged "$r" filled

# --- the plugin's text changed, the section didn't: update

t="$work/templates-2"
cp -R "$TEMPLATES" "$t"
printf -- '- A rule added in a newer version.\n' >>"$t/workflow.md"
snapshot "$r" before-update
out=$(md plan "$r" "$t")
assert_exit 0 test "$(action "$out" workflow)" = "update"
assert_unchanged "$r" before-update

chmod 600 "$r/AGENTS.md"
outside "$r/AGENTS.md" >"$work/outside-before"
out=$(md apply "$r" "$t")
assert_actions "$out" "project:keep decisions:keep workflow:update testing:keep tools:keep models:keep communication:keep"
assert_contains "$(cat "$r/AGENTS.md")" "- A rule added in a newer version.

<!-- dev-workflow:end workflow -->"
assert_markdown_form "$r/AGENTS.md"
assert_exit 0 test "$(ledger_of "$r" workflow)" = "$(text_hash "$t/workflow.md")"
# Text outside the markers is byte for byte the same, and the mode is kept.
outside "$r/AGENTS.md" >"$work/outside-after"
assert_file_same "$work/outside-before" "$work/outside-after"
# shellcheck disable=SC2012 # Only the mode is read.
assert_exit 0 test "$(ls -l "$r/AGENTS.md" | cut -c 1-10)" = "-rw-------"
# No temp file is left in the folder.
assert_exit 0 test "$(find "$r" -name '.dw-write.*' | wc -l)" -eq 0

snapshot "$r" updated
out=$(md apply "$r" "$t")
assert_actions "$out" "$(all_actions keep)"
assert_unchanged "$r" updated

# --- the project edited a section: conflict, the edit stays, the diff is shown

sed 's/^- A flaky test is a bug.*/- Our own rule on flaky tests./' "$r/AGENTS.md" >"$work/edited"
cp "$work/edited" "$r/AGENTS.md"
printf -- '- Another newer rule.\n' >>"$t/testing.md"
snapshot "$r" edited
out=$(md apply "$r" "$t")
assert_exit 0 test "$(action "$out" testing)" = "conflict"
assert_unchanged "$r" edited
diff=$(field "$out" testing diff)
assert_contains "$diff" "+- Our own rule on flaky tests."
assert_contains "$diff" "-- A flaky test is a bug"
assert_contains "$diff" "-- Another newer rule."
# Only the edited section is a conflict, and the others carry no diff.
assert_exit 0 test "$(printf '%s\n' "$out" | jq -s 'map(select(.diff)) | length')" -eq 1

# A section the project made the same as the plugin's text is managed again.
awk -v tpl="$t/testing.md" '$0 == "<!-- dev-workflow:end testing -->" {
    while ((getline line < tpl) > 0) print line; skip = 0 }
  !skip { print } $0 == "<!-- dev-workflow:begin testing -->" { skip = 1 }' \
  "$work/edited.agents" >"$r/AGENTS.md"
cp "$r/AGENTS.md" "$work/same"
out=$(md apply "$r" "$t")
assert_exit 0 test "$(action "$out" testing)" = "keep"
assert_exit 0 test "$(ledger_of "$r" testing)" = "$(text_hash "$t/testing.md")"
assert_file_same "$r/AGENTS.md" "$work/same"

# --- markers but no ledger entry: treated as edited

cp "$work/first.agents" "$r/AGENTS.md"
cp "$work/first.json" "$r/.claude/dev-workflow.json"
sed 's/^- Lead with the outcome.*/- Our own way of reporting./' "$r/AGENTS.md" >"$work/edited"
cp "$work/edited" "$r/AGENTS.md"
rm "$r/.claude/dev-workflow.json"
out=$(md apply "$r" "$t")
assert_exit 0 test "$(action "$out" communication)" = "conflict"
assert_contains "$(field "$out" communication diff)" "+- Our own way of reporting."
assert_exit 0 test "$(action "$out" decisions)" = "keep"
# Unchanged from the plugin's current text: recorded again, but the file is the same.
assert_exit 0 test "$(ledger_of "$r" decisions)" = "$(text_hash "$t/decisions.md")"
assert_exit 0 test -z "$(ledger_of "$r" communication)"
# A changed template with no record is still the project's text: not replaced.
assert_exit 0 test "$(action "$out" workflow)" = "conflict"
assert_file_same "$r/AGENTS.md" "$work/edited"

# --- a section the project removed stays removed

r="$work/removed"
mkdir -p "$r"
md apply "$r" >/dev/null
awk '/^<!-- dev-workflow:begin models -->/ { skip = 1 } !skip { print }
  /^<!-- dev-workflow:end models -->/ { skip = 0 }' "$r/AGENTS.md" >"$work/no-models"
cp "$work/no-models" "$r/AGENTS.md"
out=$(md apply "$r")
assert_exit 0 test "$(action "$out" models)" = "conflict"
assert_file_same "$r/AGENTS.md" "$work/no-models"

# --- an unknown section from a newer version is kept and reported

r="$work/unknown"
mkdir -p "$r"
md apply "$r" >/dev/null
printf '\n<!-- dev-workflow:begin future -->\n## Future\n\nFrom a newer version.\n<!-- dev-workflow:end future -->\n' >>"$r/AGENTS.md"
snapshot "$r" unknown
out=$(md apply "$r")
assert_exit 0 test "$(action "$out" future)" = "keep"
assert_exit 0 test -n "$(field "$out" future detail)"
assert_unchanged "$r" unknown

# --- an existing file: the project's text stays, sections are added after it

r="$work/existing"
mkdir -p "$r"
printf '# Mine\n\nOur own text.\n' >"$r/AGENTS.md"
cp "$r/AGENTS.md" "$work/own"
out=$(md apply "$r")
assert_actions "$out" "$(all_actions create)"
assert_exit 0 test "$(head -c "$(wc -c <"$work/own")" "$r/AGENTS.md")" = "$(cat "$work/own")"
assert_exit 1 grep -q '^## Stack$' "$r/AGENTS.md"
assert_exit 0 test "$(sed -n 4p "$r/AGENTS.md")" = ""
assert_exit 0 test "$(sed -n 5p "$r/AGENTS.md")" = "<!-- dev-workflow:begin decisions -->"

# A missing section goes back next to the others, in order.
r="$work/partial"
mkdir -p "$r"
printf '# Mine\n\n' >"$r/AGENTS.md"
{
  printf '<!-- dev-workflow:begin decisions -->\n'
  cat "$TEMPLATES/decisions.md"
  printf '<!-- dev-workflow:end decisions -->\n\n## Own part\n\nText.\n\n<!-- dev-workflow:begin tools -->\n'
  cat "$TEMPLATES/tools.md"
  printf '<!-- dev-workflow:end tools -->\n\n## Last\n\nEnd.\n'
} >>"$r/AGENTS.md"
outside "$r/AGENTS.md" >"$work/outside-before"
out=$(md apply "$r")
assert_actions "$out" "project:keep decisions:keep workflow:create testing:create tools:keep models:create communication:create"
grep -E '^(<!-- dev-workflow:begin |## Own part|## Last)' "$r/AGENTS.md" | sed 's/<!-- dev-workflow:begin //; s/ -->//' | tr '\n' ' ' >"$work/order"
assert_exit 0 test "$(cat "$work/order")" = "decisions workflow testing ## Own part tools models communication ## Last "

# --- markers in a code fence are the project's text

r="$work/fenced"
mkdir -p "$r"
# shellcheck disable=SC2016 # Backticks are the fence, not a command.
printf '# Mine\n\n```markdown\n<!-- dev-workflow:begin workflow -->\nAn example.\n<!-- dev-workflow:end workflow -->\n```\n' >"$r/AGENTS.md"
cp "$r/AGENTS.md" "$work/own"
out=$(md apply "$r")
assert_exit 0 test "$(action "$out" workflow)" = "create"
assert_exit 0 test "$(head -c "$(wc -c <"$work/own")" "$r/AGENTS.md")" = "$(cat "$work/own")"
assert_exit 0 test "$(grep -c '^<!-- dev-workflow:begin workflow -->$' "$r/AGENTS.md")" -eq 2

# --- old blocks

# web-6 exactly as published: replaced where it was, its headings gone.
r="$work/web6"
mkdir -p "$r"
{ printf '# Mine\n\nOur own text.\n\n'; block 6; printf '\n## Own rules\n\nKeep me.\n'; } >"$r/AGENTS.md"
out=$(md apply "$r")
assert_exit 0 test "$(action "$out" legacy:web-6)" = "update"
assert_exit 0 test "$(action "$out" workflow)" = "create"
for heading in '## Web Dev Workflow Rules' '### Conventional Commits' '### Commit Discipline' \
  '### Serena for Code Intelligence'; do
  assert_exit 1 grep -qx "$heading" "$r/AGENTS.md"
done
assert_exit 0 test "$(head -n 4 "$r/AGENTS.md")" = "# Mine

Our own text."
assert_exit 0 test "$(sed -n 5p "$r/AGENTS.md")" = "<!-- dev-workflow:begin decisions -->"
assert_contains "$(tail -n 5 "$r/AGENTS.md")" "<!-- dev-workflow:end communication -->

## Own rules

Keep me."
snapshot "$r" web6
out=$(md apply "$r")
assert_actions "$out" "$(all_actions keep)"
assert_unchanged "$r" web6

# web-6 with one subsection edited: that one stays under its heading and is reported.
r="$work/web6-edited"
mkdir -p "$r"
{ printf '# Mine\n\n'; block 6 | sed 's/timely/prompt/'; } >"$r/AGENTS.md"
out=$(md apply "$r")
assert_exit 0 test "$(action "$out" "legacy:web-6")" = "update"
assert_exit 0 test "$(action "$out" "legacy:web-6:Commit Discipline")" = "conflict"
diff=$(field "$out" "legacy:web-6:Commit Discipline" diff)
assert_contains "$diff" "+After completing"
assert_contains "$diff" "prompt."
assert_contains "$diff" "-After completing"
assert_exit 0 grep -qx '## Web Dev Workflow Rules' "$r/AGENTS.md"
assert_exit 0 grep -qx '### Commit Discipline' "$r/AGENTS.md"
assert_exit 0 grep -q 'focused and prompt\.' "$r/AGENTS.md"
for heading in '### Conventional Commits' '### Test-Driven Development' '### Latest Stable Versions'; do
  assert_exit 1 grep -qx "$heading" "$r/AGENTS.md"
done
snapshot "$r" web6-edited
out=$(md apply "$r")
assert_exit 0 test "$(action "$out" "legacy:web-6:Commit Discipline")" = "conflict"
assert_unchanged "$r" web6-edited

# The issues block: replaced, or kept and reported when edited.
r="$work/issues"
mkdir -p "$r"
{ printf '# Mine\n\n'; cat "$LEGACY/issues.md"; } >"$r/AGENTS.md"
out=$(md apply "$r")
assert_exit 0 test "$(action "$out" legacy:issues)" = "update"
assert_exit 1 grep -q 'GitHub Issue-Driven Workflow' "$r/AGENTS.md"
assert_exit 1 grep -q '### 1. Understand the issue' "$r/AGENTS.md"

r="$work/issues-edited"
mkdir -p "$r"
{ printf '# Mine\n\n'; sed 's/Report the PR URL/Post the PR URL/' "$LEGACY/issues.md"; } >"$r/AGENTS.md"
out=$(md apply "$r")
assert_exit 0 test "$(action "$out" legacy:issues)" = "conflict"
assert_contains "$(field "$out" legacy:issues diff)" "+- Post the PR URL"
assert_exit 0 grep -q 'Post the PR URL' "$r/AGENTS.md"
assert_exit 0 grep -q '### 1. Understand the issue' "$r/AGENTS.md"

# --- an old block in CLAUDE.md: Task 12 moves it into AGENTS.md first

r="$work/claude"
mkdir -p "$r"
{ printf '# Mine\n\n'; block 5; } >"$r/CLAUDE.md"
cp "$r/CLAUDE.md" "$work/claude.md"
md apply "$r" >/dev/null
# agents-md.sh itself never touches CLAUDE.md.
assert_file_same "$r/CLAUDE.md" "$work/claude.md"
rm "$r/AGENTS.md" "$r/.claude/dev-workflow.json"
cp "$r/CLAUDE.md" "$r/AGENTS.md"
out=$(md apply "$r")
assert_exit 0 test "$(action "$out" legacy:web-5)" = "update"
assert_exit 1 grep -q 'Web Dev Workflow Rules' "$r/AGENTS.md"
assert_exit 0 grep -qx '# Mine' "$r/AGENTS.md"

# --- CRLF and a missing final newline: the content is kept

r="$work/crlf"
mkdir -p "$r"
printf '# Mine\r\n\r\nOur own text.' >"$r/AGENTS.md"
out=$(md apply "$r")
assert_actions "$out" "$(all_actions create)"
assert_exit 0 test "$(head -c 27 "$r/AGENTS.md" | od -c | tr -s ' ')" = \
  "$(printf '# Mine\r\n\r\nOur own text.\r\n\r\n' | od -c | tr -s ' ')"
# Every line keeps the file's CRLF ending, the new ones too.
assert_exit 0 test "$(awk '!/\r$/' "$r/AGENTS.md" | wc -l)" -eq 0
snapshot "$r" crlf
out=$(md apply "$r")
assert_actions "$out" "$(all_actions keep)"
assert_unchanged "$r" crlf
# An update in a CRLF file keeps CRLF.
out=$(md apply "$r" "$t")
assert_exit 0 test "$(action "$out" workflow)" = "update"
assert_exit 0 test "$(awk '!/\r$/' "$r/AGENTS.md" | wc -l)" -eq 0
# An old block in CRLF is still found.
r="$work/crlf-block"
mkdir -p "$r"
{ printf '# Mine\n\n'; block 6; } | sed 's/$/\r/' >"$r/AGENTS.md"
out=$(md apply "$r")
assert_exit 0 test "$(action "$out" legacy:web-6)" = "update"
assert_exit 1 grep -q 'Web Dev Workflow Rules' "$r/AGENTS.md"

r="$work/no-newline"
mkdir -p "$r"
printf '# Mine\n\nOur own text.' >"$r/AGENTS.md"
md apply "$r" >/dev/null
assert_exit 0 test "$(head -n 4 "$r/AGENTS.md")" = "# Mine

Our own text."

# --- errors change nothing

r="$work/broken"
mkdir -p "$r"
printf '# Mine\n\n<!-- dev-workflow:begin workflow -->\nNo end.\n' >"$r/AGENTS.md"
cp "$r/AGENTS.md" "$work/broken.md"
assert_exit 2 sh "$AGENTS_MD" apply "$r" "$TEMPLATES"
assert_file_same "$r/AGENTS.md" "$work/broken.md"
assert_exit 1 test -e "$r/.claude"
printf '<!-- dev-workflow:begin tools -->\nA\n<!-- dev-workflow:end tools -->\n<!-- dev-workflow:begin tools -->\nB\n<!-- dev-workflow:end tools -->\n' >"$r/AGENTS.md"
assert_exit 2 sh "$AGENTS_MD" apply "$r" "$TEMPLATES"
printf '<!-- dev-workflow:end tools -->\n' >"$r/AGENTS.md"
assert_exit 2 sh "$AGENTS_MD" plan "$r" "$TEMPLATES"
printf '<!-- dev-workflow:begin tools -->\n<!-- dev-workflow:begin models -->\n<!-- dev-workflow:end models -->\n<!-- dev-workflow:end tools -->\n' >"$r/AGENTS.md"
assert_exit 2 sh "$AGENTS_MD" plan "$r" "$TEMPLATES"

# A broken project file stops it before anything is written.
r="$work/bad-ledger"
mkdir -p "$r/.claude"
printf '{ broken\n' >"$r/.claude/dev-workflow.json"
assert_exit 2 sh "$AGENTS_MD" apply "$r" "$TEMPLATES"
assert_exit 1 test -e "$r/AGENTS.md"

# A symlinked AGENTS.md isn't written through.
r="$work/link"
mkdir -p "$r"
printf '# Elsewhere\n' >"$work/elsewhere.md"
ln -s "$work/elsewhere.md" "$r/AGENTS.md"
assert_exit 2 sh "$AGENTS_MD" apply "$r" "$TEMPLATES"
assert_exit 0 test -L "$r/AGENTS.md"

# Bad usage and a templates folder missing a section.
assert_exit 2 sh "$AGENTS_MD"
assert_exit 2 sh "$AGENTS_MD" frob "$work/new" "$TEMPLATES"
assert_exit 2 sh "$AGENTS_MD" plan "$work/no-such-dir" "$TEMPLATES"
mkdir -p "$work/short-templates"
cp "$TEMPLATES/project.md" "$work/short-templates/"
assert_exit 2 sh "$AGENTS_MD" plan "$work/new" "$work/short-templates"

# A .claude folder, where the ledger is, that leads out of the project is refused.
r=$work/escape
mkdir -p "$r" "$work/away"
ln -s "$work/away" "$r/.claude"
assert_exit 2 sh "$AGENTS_MD" apply "$r" "$TEMPLATES"
assert_contains "$_assert_output" 'outside the project'
assert_exit 1 test -e "$r/AGENTS.md"
assert_exit 0 test -z "$(ls -A "$work/away")"
