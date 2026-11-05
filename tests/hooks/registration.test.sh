#!/bin/sh
# Tests how the plugin registers its hooks and settings: hooks.json, plugin.json, that
# the scripts work from a copy that lost its modes, and that the live test stays out of
# scripts/check and skips visibly.

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
# shellcheck source=tests/lib/assert.sh
. "$ROOT/tests/lib/assert.sh"
# shellcheck source=tests/lib/hook.sh
. "$ROOT/tests/lib/hook.sh"

plugin="$ROOT/plugins/dev-workflow"
hooks_json="$plugin/hooks/hooks.json"
manifest="$plugin/.claude-plugin/plugin.json"

unset HOOK_PATH

# --- hooks.json

assert_exit 0 test -f "$hooks_json"

# handler_of <event> <script name>: the one handler running that script, as JSON.
handler_of() {
  jq -ce --arg event "$1" --arg args "\${CLAUDE_PLUGIN_ROOT}/scripts/$2" '
    [.hooks[$event][].hooks[] | select(.args == [$args])]
    | select(length == 1) | .[0]' "$hooks_json" ||
    _assert_fail "no one handler for $2 on $1"
}

# Exec form, through sh, because a cached plugin may lose its modes.
for pre_tool_use in hook-bash.sh hook-workflow-edit.sh hook-github-mcp.sh; do
  handler=$(handler_of PreToolUse "$pre_tool_use")
  printf '%s' "$handler" | jq -e '
    .type == "command" and .command == "sh" and .onFailure == "block" and (.timeout | type == "number")
  ' >/dev/null || _assert_fail "$pre_tool_use isn't registered as it should be: $handler"
done

handler=$(handler_of SessionStart hook-session-start.sh)
printf '%s' "$handler" | jq -e '
  .type == "command" and .command == "sh" and (.timeout | type == "number") and (has("onFailure") | not)
' >/dev/null || _assert_fail "the session-start check isn't registered as it should be: $handler"

# Nothing else is registered.
assert_exit 0 jq -e '
  (.hooks | keys) == ["PreToolUse", "SessionStart"]
  and ([.hooks[][].hooks[]] | length) == 4
' "$hooks_json"

# matcher_of <script name>
matcher_of() {
  jq -re --arg args "\${CLAUDE_PLUGIN_ROOT}/scripts/$1" \
    '.hooks.PreToolUse[] | select(.hooks[].args == [$args]) | .matcher' "$hooks_json"
}
assert_exit 0 test "$(matcher_of hook-bash.sh)" = 'Bash'
assert_exit 0 test "$(matcher_of hook-workflow-edit.sh)" = 'Write|Edit'
assert_exit 0 test "$(matcher_of hook-github-mcp.sh)" = 'mcp__.*[Gg]it[Hh]ub.*'

# --- plugin.json

assert_exit 0 jq -e '
  (.author.name | type == "string")
  and (.description | test("methodology"))
  and (.userConfig | keys | sort) == ([
    "model_noncoding", "model_noncoding_alt", "model_coding", "effort_coding",
    "reviewer_name", "reviewer_command", "review_threshold_lines", "maintenance_interval_days"
  ] | sort)
  and .userConfig.model_noncoding.default == "claude-fable-5-1"
  and .userConfig.model_noncoding_alt.default == "gpt-6-astra"
  and .userConfig.model_coding.default == "claude-opus-5-5"
  and .userConfig.effort_coding.default == "high"
  and .userConfig.reviewer_name.default == "GPT-6.1 Sol (OpenAI, high effort, read-only)"
  and .userConfig.reviewer_command.default == "codex exec -m gpt-6.1-sol -c model_reasoning_effort=high --sandbox read-only \"<brief>\" < /dev/null"
  and .userConfig.review_threshold_lines.default == 300
  and .userConfig.maintenance_interval_days.default == 30
  and .userConfig.review_threshold_lines.type == "number"
  and .userConfig.maintenance_interval_days.type == "number"
  and ([.userConfig[] | (.title | type == "string") and (.description | type == "string")] | all)
' "$manifest"

# --- A copy that lost its modes, as a cached plugin may: each script as hooks.json runs it

copy="$(tmp_dir)/the plugin"
cp -R "$plugin" "$copy"
find "$copy" -type f -exec chmod a-x {} +

# path_in_copy <script name>: the path hooks.json gives sh for it, in the copy.
path_in_copy() {
  jq -re --arg args "\${CLAUDE_PLUGIN_ROOT}/scripts/$1" --arg root "$copy" '
    [.hooks[][].hooks[].args[0] | select(. == $args)][0]
    | sub("\\$\\{CLAUDE_PLUGIN_ROOT\\}"; $root)' "$hooks_json"
}

repo="$(tmp_dir)/a b/repo"
new_repo "$repo"
mkdir -p "$repo/.claude"
printf '{"testCommands": ["npm test"], "databaseResetCommands": ["npm run db:reset"]}\n' >"$repo/.claude/dev-workflow.json"
CLAUDE_PROJECT_DIR=$repo
export CLAUDE_PROJECT_DIR
cd "$repo" || exit 1

assert_exit 1 test -x "$(path_in_copy hook-bash.sh)"

hook=$(path_in_copy hook-bash.sh)
assert_decision deny "$hook" "$(bash_input 'git commit --no-verify -m x')"
assert_decision deny "$hook" "$(bash_input 'npm test && gh pr merge 1 --squash --subject x --body ""')"
assert_decision ask "$hook" "$(bash_input 'npm run db:reset')"
assert_decision none "$hook" "$(bash_input 'ls')"

hook=$(path_in_copy hook-workflow-edit.sh)
workflow_edit=$(jq -n --arg path "$repo/.github/workflows/ci.yml" '{file_path: $path, content: "on: pull_request"}')
workflow_edit=$(tool_input Write "$workflow_edit")
assert_decision ask "$hook" "$workflow_edit"
assert_contains "$(reason_of "$hook" "$workflow_edit")" 'pull_request'

hook=$(path_in_copy hook-github-mcp.sh)
attributed=$(tool_input mcp__github__create_pull_request '{"title": "Generated with Claude Code"}')
assert_decision deny "$hook" "$attributed"
assert_contains "$(reason_of "$hook" "$attributed")" 'attribution'

git -C "$repo" config core.hooksPath .githooks
output=$(sh "$(path_in_copy hook-session-start.sh)" </dev/null) || _assert_fail "the session-start check failed in the copy"
assert_contains "$output" 'pluginVersion'

# --- The live test: never from scripts/check, and it says when it skips

live="$ROOT/tests/verify_only/live-hooks.test.sh"
assert_exit 0 test -f "$live"
assert_not_contains "$(sed -n 's/^.*run\.sh//p' "$ROOT/scripts/check")" 'verify_only'
ran_by_check=$(tmp_dir)
mkdir -p "$ran_by_check/verify_only"
printf 'echo ran\nexit 1\n' >"$ran_by_check/verify_only/live-hooks.test.sh"
printf 'exit 0\n' >"$ran_by_check/other.test.sh"
assert_not_contains "$(sh "$ROOT/tests/run.sh" "$ran_by_check" 2>&1)" 'live-hooks'

skipped=$(DW_SKIP_LIVE=1 sh "$live" 2>&1) || _assert_fail "the live test failed when told to skip: $skipped"
assert_contains "$skipped" 'skipped'
assert_contains "$skipped" 'DW_SKIP_LIVE'

no_claude=$(tmp_dir)
shell_path=$(command -v sh)
skipped=$(PATH=$no_claude DW_SKIP_LIVE='' "$shell_path" "$live" 2>&1) || _assert_fail "the live test failed without claude: $skipped"
assert_contains "$skipped" 'skipped'
assert_contains "$skipped" 'claude'
