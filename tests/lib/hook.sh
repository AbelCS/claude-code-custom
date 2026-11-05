#!/bin/sh
# Helpers for testing Claude Code hook scripts. Source this after assert.sh; don't
# run it.
#
# Set HOOK_PATH to run the hook with that PATH, as when a tool is missing. These
# helpers keep using the test's own PATH, so they can still read what the hook said.

# bash_input <cmd>: the JSON Claude Code sends a hook before running a command.
bash_input() {
  jq -n --arg cmd "$1" --arg cwd "$PWD" \
    '{hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: $cmd}, cwd: $cwd}'
}

# tool_input <tool> <json>: the same for any tool, with json as its tool_input.
tool_input() {
  jq -n --arg tool "$1" --argjson input "$2" --arg cwd "$PWD" \
    '{hook_event_name: "PreToolUse", tool_name: $tool, tool_input: $input, cwd: $cwd}'
}

# Runs <script> with <json> on stdin and sets _hook_output. A hook decides by what it
# prints, so any other exit status is a failure of the hook.
_hook_run() {
  _hook_shell=$(command -v sh) || return 1
  if ! _hook_output=$(printf '%s' "$2" | env PATH="${HOOK_PATH:-$PATH}" "$_hook_shell" "$1"); then
    printf 'hook: %s failed, having printed: %s\n' "$1" "$_hook_output" >&2
    return 1
  fi
}

# decision_of <script> <json>: prints deny, ask or none. Prints nothing and fails if
# the hook failed or printed anything but a complete decision, so that comparing the
# result fails too.
decision_of() {
  _hook_run "$1" "$2" || return 1
  if [ -z "$_hook_output" ]; then
    echo none
    return 0
  fi
  if ! printf '%s' "$_hook_output" | jq -er '
    .hookSpecificOutput
    | select(.hookEventName == "PreToolUse" and (.permissionDecisionReason | type == "string"))
    | .permissionDecision
    | select(. == "deny" or . == "ask")' 2>/dev/null; then
    printf 'hook: %s printed something other than a decision: %s\n' "$1" "$_hook_output" >&2
    return 1
  fi
}

# reason_of <script> <json>: prints the reason the hook gave, and nothing if it gave
# none.
reason_of() {
  _hook_run "$1" "$2" || return 1
  [ -n "$_hook_output" ] || return 0
  printf '%s' "$_hook_output" | jq -j '.hookSpecificOutput.permissionDecisionReason'
}

# assert_decision <deny|ask|none> <script> <json>
assert_decision() {
  _hook_decision=$(decision_of "$2" "$3")
  [ "$_hook_decision" = "$1" ] || _assert_fail "expected $1, got \"$_hook_decision\" for: $3"
}
