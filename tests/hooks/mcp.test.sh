#!/bin/sh
# Tests the rules on GitHub MCP tools, as a table of calls and the decision each gets, run
# through the real hook in a real repo.
#
# The tool list, read from the README of github/github-mcp-server on 2026-11-05. The
# server is remote, so a tool can appear there at any time, and the hook works from a
# name's shape instead of this list.
#
#   Read: get_* list_* search_* *_read, also actions_get actions_list projects_get
#     projects_list ui_get github_support_docs_search, which don't have the read shape
#     and so are scanned like any other tool.
#   Merge: merge_pull_request, with commit_title, commit_message, merge_method,
#     expectedHeadSha, owner, repo, pullNumber.
#   Text people read, by tool and field:
#     create_pull_request, update_pull_request: title, body
#     issue_write: title, body, issue_fields[]
#     add_issue_comment, update_issue_comment, add_reply_to_pull_request_comment,
#       pull_request_review_write, add_comment_to_pending_review: body
#     discussion_comment_write, create_gist, update_gist, label_write, sub_issue_write,
#       create_repository, projects_write and others: various
#     create_or_update_file: message, content
#     push_files: message, files[].path, files[].content

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
# shellcheck source=tests/lib/assert.sh
. "$ROOT/tests/lib/assert.sh"
# shellcheck source=tests/lib/hook.sh
. "$ROOT/tests/lib/hook.sh"

plugin="$ROOT/plugins/dev-workflow"
hook="$plugin/scripts/hook-github-mcp.sh"

unset HOOK_PATH

repo="$(tmp_dir)/a b/repo"
new_repo "$repo"
mkdir -p "$repo/.claude"
printf '{}\n' >"$repo/.claude/dev-workflow.json"
CLAUDE_PROJECT_DIR=$repo
export CLAUDE_PROJECT_DIR
cd "$repo" || exit 1

# rule <deny|none> <tool, after the prefix> <tool_input as JSON> [text the reason must hold]
rule() {
  _rule_input=$(tool_input "mcp__plugin_github_github__$2" "$3")
  assert_decision "$1" "$hook" "$_rule_input"
  [ -z "${4:-}" ] || assert_contains "$(reason_of "$hook" "$_rule_input")" "$4"
}

attributed='"Why.\n\nCo-Authored-By: Claude <noreply@anthropic.com>"'

# --- The matcher in hooks.json, tested as Claude Code uses it: a pattern with these
# characters is a regular expression, matching anywhere in the name

matcher=$(jq -re '.hooks.PreToolUse[]
  | select(.hooks[].args == ["${CLAUDE_PLUGIN_ROOT}/scripts/hook-github-mcp.sh"])
  | .matcher' "$plugin/hooks/hooks.json") || _assert_fail "hooks.json has no matcher for the GitHub hook"
matched() {
  printf '%s\n' "$1" | grep -Eq "$matcher"
}
for name in \
  mcp__plugin_github_github__create_pull_request \
  mcp__plugin_github_github__get_me \
  mcp__github__merge_pull_request \
  mcp__github-enterprise__issue_write \
  mcp__claude_ai_GitHub__x \
  mcp__claude_ai_Github__create_pull_request; do
  assert_exit 0 matched "$name"
done
for name in Bash Write mcp__plugin_vercel_vercel__list_projects github mcp_github_x; do
  assert_exit 1 matched "$name"
done

# The hook reads a connector's tools by the same last part of the name.
connector_call=$(tool_input mcp__claude_ai_GitHub__create_pull_request "{\"title\": \"feat: x\", \"body\": $attributed}")
assert_decision deny "$hook" "$connector_call"
assert_contains "$(reason_of "$hook" "$connector_call")" 'attribution'
connector_call=$(tool_input mcp__claude_ai_GitHub__get_me '{}')
assert_decision none "$hook" "$connector_call"

# --- Attribution in any string field of a tool that isn't clearly read-only

rule deny create_pull_request "{\"title\": \"feat: x\", \"body\": $attributed}" 'attribution'
rule deny create_pull_request '{"title": "Generated with Claude Code", "body": "Closes #1"}' 'attribution'
rule deny update_pull_request "{\"pullNumber\": 1, \"body\": $attributed}" 'attribution'
rule deny issue_write "{\"method\": \"create\", \"title\": \"x\", \"body\": $attributed}" 'attribution'
rule deny issue_write '{"method": "update", "title": "Generated with Claude Code"}' 'attribution'
rule deny add_issue_comment "{\"issue_number\": 1, \"body\": $attributed}" 'attribution'
rule deny update_issue_comment "{\"body\": $attributed}" 'attribution'
rule deny pull_request_review_write "{\"method\": \"create\", \"body\": $attributed}" 'attribution'
rule deny create_or_update_file "{\"path\": \"a.md\", \"message\": $attributed, \"content\": \"x\"}" 'attribution'

# Further down, and at the very start of a field.
rule deny push_files "{\"message\": \"feat: x\", \"files\": [{\"path\": \"a.md\", \"content\": $attributed}]}" 'attribution'
rule deny issue_write '{"issue_fields": [{"field_name": "a", "value": {"text": ["Assisted-by: Claude"]}}]}' 'attribution'
rule deny add_issue_comment '{"body": "**Co-Authored-By:** Claude"}' 'attribution'

# Written as a backslash and an n, which people and tools mean as a line.
rule deny add_issue_comment '{"body": "Why.\\n\\nCo-Authored-By: Claude"}' 'attribution'

# A tool on no list, by any prefix, is scanned too.
rule deny some_future_tool "{\"text\": $attributed}" 'attribution'
for tool in \
  mcp__github__add_issue_comment \
  mcp__github-enterprise__add_issue_comment \
  add_issue_comment; do
  assert_decision deny "$hook" "$(tool_input "$tool" "{\"body\": $attributed}")"
done
# Tools with no read shape, whatever they do.
rule deny actions_get "{\"text\": $attributed}" 'attribution'
rule deny github_support_docs_search "{\"query\": $attributed}" 'attribution'

# --- What passes

rule none create_pull_request '{"title": "feat: x", "body": "Closes #1", "draft": false, "reviewers": ["ana"]}'
rule none update_pull_request '{"pullNumber": 1, "body": "The hook reads the Claude Code input."}'
rule none add_issue_comment '{"issue_number": 1, "body": "**Co-Authored-By:** Ana Ruiz"}'
rule none add_issue_comment '{"issue_number": 1, "body": "The **Co-Authored-By:** form is rejected."}'
rule none some_future_tool '{}'
rule none some_future_tool '{"count": 3, "flag": true, "nothing": null}'
assert_decision none "$hook" "$(jq -n '{tool_name: "mcp__github__x"}')"
# A field's name isn't text anyone reads.
rule none some_future_tool '{"Generated with Claude": "x"}'

# --- Read tools aren't scanned, whatever they're searching for

rule none get_me '{}'
rule none get_file_contents '{"path": "Generated with Claude Code"}'
rule none list_issues "{\"labels\": [$attributed]}"
rule none search_pull_requests '{"query": "Generated with Claude Code"}'
rule none search_code '{"query": "Co-Authored-By: Claude"}'
rule none pull_request_read '{"method": "get_diff", "pullNumber": 1}'
rule none issue_read '{"method": "get", "text": "Generated with Claude Code"}'
rule none custom_properties_read '{"text": "Generated with Claude Code"}'
# The name's shape is what counts: this reads merges rather than making one.
rule none get_merge_pull_request_status '{}'
rule none list_merged_pull_requests '{}'
# Only the start of a name, or the end of it.
rule deny getter_tool "{\"text\": $attributed}" 'attribution'
rule deny forget_issue "{\"text\": $attributed}" 'attribution'
rule deny read_issue "{\"text\": $attributed}" 'attribution'
rule deny issue_reader "{\"text\": $attributed}" 'attribution'

# --- Merge tools

squash='"owner": "o", "repo": "r", "pullNumber": 1, "merge_method": "squash"'
rule none merge_pull_request "{$squash}"
rule none merge_pull_request "{$squash, \"commit_title\": \"feat: x (#1)\"}"
rule none merge_pull_request "{$squash, \"commit_title\": \"feat: x (#1)\", \"commit_message\": \"\"}"
rule none merge_pull_request "{$squash, \"commit_message\": null}"

rule deny merge_pull_request '{"pullNumber": 1}' 'squash'
rule deny merge_pull_request '{"merge_method": "merge"}' 'squash'
rule deny merge_pull_request '{"merge_method": "rebase"}' 'squash'
rule deny merge_pull_request '{"merge_method": "Squash"}' 'squash'
rule deny merge_pull_request '{"merge_method": ["squash"]}' 'squash'
rule deny merge_pull_request "{$squash, \"commit_message\": \"text\"}" 'squash'
rule deny merge_pull_request "{$squash, \"commit_message\": \" \"}" 'squash'
rule deny merge_pull_request "{$squash, \"commit_message\": 1}" 'squash'
rule deny merge_pull_request '{"merge_method": "squash", "commit_message": false}' 'squash'
rule deny merge_pull_request '{"commit_message": "", "commit_title": "feat: x"}' 'squash'

# A title becomes a commit no git hook sees, and every other field still counts.
rule deny merge_pull_request "{$squash, \"commit_title\": \"Generated with Claude Code\"}" 'attribution'
rule deny merge_pull_request "{$squash, \"other\": [$attributed]}" 'attribution'

# Any name with both words, by any prefix.
rule deny pull_request_merge '{"merge_method": "merge"}' 'squash'
rule deny merge_pull_request_now '{"merge_method": "merge"}' 'squash'
rule none merge_pull_request_now "{$squash}"
assert_decision deny "$hook" "$(tool_input mcp__github__merge_pull_request '{"merge_method": "merge"}')"
# Without both, it isn't one.
rule none update_pull_request '{"merge_method": "merge"}'
rule none update_pull_request_branch '{"pullNumber": 1}'
rule none merge_branches '{"merge_method": "merge"}'

# --- Input it can't read

assert_decision deny "$hook" 'not json'
assert_decision deny "$hook" '{"tool_name": "mcp__github__merge_pull_request", "tool_input": "not an object"}'
assert_decision deny "$hook" '{"tool_name": "mcp__github__x", "tool_input": "Generated with Claude Code"}'
assert_decision none "$hook" '{"tool_name": "mcp__github__x", "tool_input": "clean text"}'

# --- Doing nothing outside a project

bare="$(tmp_dir)/bare"
mkdir "$bare"
no_tools=$(tmp_dir)
CLAUDE_PROJECT_DIR=$bare
rule none add_issue_comment "{\"body\": $attributed}"
rule none merge_pull_request '{"merge_method": "merge"}'
# Without jq too, and nothing outside the shell runs before the gate.
input=$(tool_input mcp__github__merge_pull_request '{"merge_method": "merge"}')
HOOK_PATH=$no_tools
assert_decision none "$hook" "$input"
CLAUDE_PROJECT_DIR=$repo
# In a project, no jq blocks.
assert_decision deny "$hook" "$input"
assert_contains "$(reason_of "$hook" "$input")" 'jq'
unset HOOK_PATH

# --- The hook runs from another folder and by a relative path

assert_exit 0 test -x "$hook"
assert_contains "$(cd "$plugin/scripts" && printf '%s' "$input" | sh hook-github-mcp.sh)" '"deny"'
assert_contains "$(cd "$plugin" && printf '%s' "$input" | sh scripts/hook-github-mcp.sh)" '"deny"'

# --- What the hook relies on, missing or failing, blocks

clean_input=$(tool_input mcp__github__add_issue_comment '{"body": "Clean"}')
fake_tools=$(tmp_dir)
for tool in jq sed tr cat; do
  ln -s "$(command -v "$tool")" "$fake_tools/$tool"
done
cat >"$fake_tools/grep" <<'FAKE'
#!/bin/sh
exit 2
FAKE
chmod +x "$fake_tools/grep"
HOOK_PATH=$fake_tools
assert_decision deny "$hook" "$clean_input"
assert_contains "$(reason_of "$hook" "$clean_input")" 'attribution'
unset HOOK_PATH

partial="$(tmp_dir)/partial"
mkdir -p "$partial/scripts/lib"
cp "$hook" "$partial/scripts/"
cp "$plugin/scripts/lib/"* "$partial/scripts/lib/"
assert_decision deny "$partial/scripts/hook-github-mcp.sh" "$clean_input"
assert_contains "$(reason_of "$partial/scripts/hook-github-mcp.sh" "$clean_input")" 'dw-lib.sh'
