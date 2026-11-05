#!/bin/sh
# tools.sh [<root>]: which tools setup needs are there, each with its install command.
# shellcheck disable=SC2016 # The dollars in quotes are jq's and the stubs'.

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
# shellcheck source=tests/lib/assert.sh
. "$ROOT/tests/lib/assert.sh"

TOOLS="$ROOT/plugins/dev-workflow/scripts/setup/tools.sh"
JQ=$(command -v jq)
SH=$(command -v sh)
work=$(tmp_dir)

SKILLS="brainstorming writing-plans test-driven-development systematic-debugging verification-before-completion receiving-code-review finishing-a-development-branch"

# bin_with <tool...>: a folder holding only these tools, plus stub gh and claude.
bin_with() {
  _bin=$(mktemp -d "$work/bin.XXXXXX") || _assert_fail "no temp folder"
  for _tool in "$@"; do
    ln -s "$(command -v "$_tool")" "$_bin/$_tool" || _assert_fail "no $_tool"
  done
  printf '#!/bin/sh\n[ "$1 $2" = "auth status" ] && exit "${GH_SIGNED_OUT:-0}"\nexit 0\n' >"$_bin/gh"
  printf '#!/bin/sh\n[ "$1" = --version ] && echo "${CLAUDE_VERSION:-2.1.300} (Claude Code)"\nexit 0\n' >"$_bin/claude"
  chmod +x "$_bin/gh" "$_bin/claude"
  printf '%s\n' "$_bin"
}

# A registry with superpowers, holding every skill but writing-plans, and context7.
config=$work/config
sp=$work/superpowers
for s in $SKILLS; do
  [ "$s" = writing-plans ] && continue
  mkdir -p "$sp/skills/$s" && printf -- '---\nname: %s\n---\n' "$s" >"$sp/skills/$s/SKILL.md"
done
mkdir -p "$config/plugins"
project=$work/project
mkdir -p "$project"
"$JQ" -n --arg sp "$sp" '{version: 2, plugins: {
  "superpowers@claude-plugins-official": [{scope: "user", installPath: $sp}],
  "context7@claude-plugins-official": [{scope: "user", installPath: "/x"}],
  "serena@claude-plugins-official": [{scope: "project", projectPath: "/another/project", installPath: "/x"}]
}}' >"$config/plugins/installed_plugins.json"

run_tools() { # <bin>: the JSON, which has to be valid
  _out=$(cd "$project" && PATH=$1 CLAUDE_CONFIG_DIR=$config "$SH" "$TOOLS" "$project" 2>&1) ||
    _assert_fail "tools.sh failed:
$_out"
  printf '%s\n' "$_out" | "$JQ" -e 'type == "object" and (.required | type == "array")' >/dev/null ||
    _assert_fail "not JSON:
$_out"
  printf '%s\n' "$_out"
}

field() { # <json> <group> <name> <field>
  printf '%s\n' "$1" | "$JQ" -c --arg g "$2" --arg n "$3" --arg f "$4" '.[$g][] | select(.name == $n) | .[$f]'
}

# --- everything required is there

bin=$(bin_with git jq)
out=$(run_tools "$bin")
for t in git gh jq claude; do
  assert_exit 0 test "$(field "$out" required "$t" present)" = true
done
assert_exit 0 test "$(field "$out" plugins superpowers present)" = true
assert_exit 0 test "$(field "$out" plugins superpowers missingSkills)" = '["writing-plans"]'
assert_exit 0 test "$(field "$out" plugins context7 present)" = true
# Installed only for another project doesn't count.
assert_exit 0 test "$(field "$out" plugins serena present)" = false
assert_contains "$(field "$out" plugins serena install)" 'claude plugin install serena@claude-plugins-official'
assert_exit 0 test "$(field "$out" plugins intent when)" = '"screens"'
assert_contains "$(field "$out" plugins intent install)" 'claude plugin marketplace add ghaida/intent'
assert_contains "$(field "$out" plugins intent install)" 'claude plugin install intent@intent'
assert_contains "$(field "$out" plugins ui-ux-pro-max install)" 'nextlevelbuilder/ui-ux-pro-max-skill'
assert_exit 0 test "$(field "$out" other codex present)" = false
assert_contains "$(field "$out" other codex install)" 'npm install -g @openai/codex'
assert_exit 0 test "$(field "$out" other browser present)" = false

# The plugin list is the session-start hook's: one file, read by both.
assert_exit 0 test "$(printf '%s\n' "$out" | "$JQ" -r '.plugins | map(.name) | join(" ")')" = \
  "superpowers context7 serena intent ui-ux-pro-max"
assert_contains "$(cat "$ROOT/plugins/dev-workflow/scripts/hook-session-start.sh")" 'lib/plugins.txt'

# Every named skill there: none missing.
mkdir -p "$sp/skills/writing-plans" && : >"$sp/skills/writing-plans/SKILL.md"
out=$(run_tools "$bin")
assert_exit 0 test "$(field "$out" plugins superpowers missingSkills)" = '[]'

# --- jq missing: still JSON, saying so, with its install command

bin=$(bin_with git)
out=$(run_tools "$bin")
assert_exit 0 test "$(field "$out" required jq present)" = false
assert_contains "$(field "$out" required jq install)" 'brew install jq'
assert_exit 0 test "$(field "$out" required git present)" = true

# --- Claude Code older than the minimum, and gh signed out

bin=$(bin_with git jq)
out=$(CLAUDE_VERSION=2.1.294 run_tools "$bin")
assert_exit 0 test "$(field "$out" required claude present)" = false
assert_contains "$(field "$out" required claude detail)" '2.1.295'
assert_contains "$(field "$out" required claude install)" 'claude update'
for v in 2.1.295 2.2.0 3.0.0; do
  out=$(CLAUDE_VERSION=$v run_tools "$bin")
  assert_exit 0 test "$(field "$out" required claude present)" = true
done
out=$(GH_SIGNED_OUT=1 run_tools "$bin")
assert_exit 0 test "$(field "$out" required gh present)" = false
assert_contains "$(field "$out" required gh install)" 'gh auth login'

# A browser tool on the PATH counts.
printf '#!/bin/sh\n' >"$bin/playwright" && chmod +x "$bin/playwright"
out=$(run_tools "$bin")
assert_exit 0 test "$(field "$out" other browser present)" = true

assert_exit 2 sh "$TOOLS" a b
echo "tools: ok"
