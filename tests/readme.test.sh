#!/bin/sh
# The README: the update steps, every setting, how to change a default, every upgrade
# note, the skills table, and the old commands only where they belong.

ROOT=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=tests/lib/assert.sh
. "$ROOT/tests/lib/assert.sh"

readme="$ROOT/README.md"
manifest="$ROOT/plugins/dev-workflow/.claude-plugin/plugin.json"
text=$(cat "$readme")

# --- install and update

assert_contains "$text" "/plugin marketplace add AbelCS/claude-code-custom"
assert_contains "$text" "/plugin install dev-workflow@claude-code-custom"
assert_contains "$text" "/dev-workflow:setup"
assert_contains "$text" "/plugin marketplace update claude-code-custom"
assert_contains "$text" "claude plugin update dev-workflow@claude-code-custom"
assert_contains "$text" "/reload-plugins"
assert_contains "$text" "claude plugin install dev-workflow@claude-code-custom"
assert_contains "$text" "2.1.295"
for tool in git gh jq Superpowers Context7 Serena intent ui-ux-pro-max; do
  assert_contains "$text" "$tool"
done

# --- every setting, with its default, and how to change one

for key in $(jq -r '.userConfig | keys[]' "$manifest"); do
  assert_contains "$text" "\`$key\`"
  default=$(jq -r --arg k "$key" '.userConfig[$k].default | tostring' "$manifest")
  assert_contains "$text" "$default"
done
assert_contains "$text" "/config"
assert_contains "$text" "How to change a default"
assert_contains "$text" "## How to use it"

# --- every skill is in the table

for dir in "$ROOT"/plugins/dev-workflow/skills/*/; do
  assert_contains "$text" "\`/dev-workflow:$(basename "$dir")\`"
done

# --- what's enforced, and what was tested

assert_contains "$text" "docs/hook-behaviour.md"
assert_contains "$text" "git hooks"
assert_contains "$text" "Claude Code hooks"

# --- upgrade notes

upgrade=$(printf '%s\n' "$text" | awk '/^## Upgrade notes/ { on = 1; next } /^## / { on = 0 } on')
assert_contains "$upgrade" "/web-dev-workflow:setup"
assert_contains "$upgrade" "/dev-workflow:enable-github-issues"
assert_contains "$upgrade" "not cached"
assert_contains "$upgrade" "enable-releases"
assert_contains "$upgrade" "RELEASE_PLEASE_TOKEN"
assert_contains "$upgrade" "GITHUB_TOKEN"
assert_contains "$upgrade" "two runs"
assert_contains "$upgrade" "Rerun \`/dev-workflow:setup\`"

# The old commands appear nowhere else.
outside=$(printf '%s\n' "$text" | awk '/^## Upgrade notes/ { on = 1; next } /^## / { on = 0 } !on')
assert_not_contains "$outside" "/web-dev-workflow:"
assert_not_contains "$outside" "enable-github-issues"

# --- developing and licence

assert_contains "$text" "scripts/check"
assert_contains "$text" "scripts/verify"
assert_contains "$text" "DW_SKIP_LIVE"
assert_contains "$text" "DW_SKIP_FIXTURES"
assert_contains "$text" "MIT"

# --- no attribution

lower=$(printf '%s\n' "$text" | tr '[:upper:]' '[:lower:]')
assert_not_contains "$lower" "co-authored-by"
assert_not_contains "$lower" "generated with"
