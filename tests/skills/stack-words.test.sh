#!/bin/sh
# Stack wording stays in stacks/. The plugin names no framework, hosting or database
# product outside plugins/dev-workflow/stacks/, apart from the stack hint names in
# detect.sh and the general "with or without row-level security" database rule.
# choose-stack names no vendor at all. Each stack file says how its stack fills the
# project file's commands and the module shape, and when it was checked. Supabase's
# reset commands are in the form setup reads.

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
# shellcheck source=tests/lib/assert.sh
. "$ROOT/tests/lib/assert.sh"

PLUGIN="$ROOT/plugins/dev-workflow"
STACKS="$PLUGIN/stacks"

# --- the words, everywhere but stacks/ and detect.sh

files=$(find "$PLUGIN" -type f ! -path "$STACKS/*" ! -path "$PLUGIN/scripts/setup/detect.sh" | sort)
[ -n "$files" ] || _assert_fail "no files found in $PLUGIN"
while IFS= read -r file; do
  text=$(tr '[:upper:]' '[:lower:]' <"$file" | sed 's/with or without row-level security//g')
  for word in nextjs supabase astro rls; do
    if printf '%s\n' "$text" | grep -qw -- "$word"; then
      _assert_fail "${file#"$ROOT"/} names \"$word\", which belongs in stacks/"
    fi
  done
  for phrase in "next.js" "row-level security" "row level security"; do
    case $text in
      *"$phrase"*) _assert_fail "${file#"$ROOT"/} says \"$phrase\", which belongs in stacks/" ;;
    esac
  done
done <<FILES
$files
FILES

# --- choose-stack names no vendor

choose="$PLUGIN/skills/choose-stack/SKILL.md"
[ -f "$choose" ] || _assert_fail "no choose-stack skill"
lower=$(tr '[:upper:]' '[:lower:]' <"$choose")
for vendor in vercel netlify aws amazon azure microsoft google gcp cloudflare heroku fly.io \
  railway digitalocean hetzner firebase neon planetscale mongodb postgres postgresql mysql \
  sqlite redis node deno bun react vue svelte angular django rails laravel litestar express \
  docker kubernetes; do
  if printf '%s\n' "$lower" | grep -qw -- "$vendor"; then
    _assert_fail "choose-stack names \"$vendor\": it names no vendor"
  fi
done

# --- the stack files

for name in node-tooling nextjs astro supabase; do
  file="$STACKS/$name.md"
  [ -f "$file" ] || _assert_fail "no stack file $name.md"
  text=$(cat "$file")
  lines=$(wc -l <"$file" | tr -d ' ')
  [ "$lines" -le 120 ] || _assert_fail "$name.md is $lines lines, not 120 or under"
  # How the stack fills the project file, field by field.
  for field in format check verify deadCode audit testCommands; do
    assert_contains "$text" "\`$field\`"
  done
  # The module shape from conventions-code, and the date the versions were checked.
  assert_contains "$text" "contracts"
  assert_contains "$text" "conventions-code"
  printf '%s\n' "$text" | grep -Eq 'checked on 20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]' ||
    _assert_fail "$name.md doesn't say the date its versions were checked on"
done

assert_contains "$(cat "$STACKS/supabase.md")" "\`databaseResetCommands\`"
assert_contains "$(cat "$STACKS/supabase.md")" "row-level security"
assert_contains "$(cat "$STACKS/supabase.md")" "read-only"
assert_contains "$(cat "$STACKS/node-tooling.md")" "node_modules"
assert_contains "$(cat "$STACKS/nextjs.md")" "node_modules/next/dist/docs/"
assert_contains "$(cat "$STACKS/astro.md")" "no database"

# Supabase's reset commands, in the form project-file.sh reads: one a line, blank lines
# and # comments left out. Each runs the CLI. The other stacks name none.
resets="$STACKS/supabase.resets"
[ -f "$resets" ] || _assert_fail "no supabase.resets"
commands=$(sed -e 's/[[:space:]]*$//' -e '/^$/d' -e '/^#/d' "$resets")
[ -n "$commands" ] || _assert_fail "supabase.resets has no commands"
while IFS= read -r command; do
  case $command in
    "supabase "* | "npx supabase "*) ;;
    *) _assert_fail "supabase.resets has a line that doesn't run the CLI: $command" ;;
  esac
done <<COMMANDS
$commands
COMMANDS
assert_contains "$commands" "supabase db reset"
for name in node-tooling nextjs astro; do
  [ ! -e "$STACKS/$name.resets" ] || _assert_fail "$name has a .resets file, but its docs name no reset"
done

# Nothing in stacks/ but the stack files and their resets.
extra=$(find "$STACKS" -type f ! -name '*.md' ! -name '*.resets')
[ -z "$extra" ] || _assert_fail "unexpected files in stacks/: $extra"
