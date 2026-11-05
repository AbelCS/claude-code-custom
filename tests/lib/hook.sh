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

# Sets _hook_field to <field> of the decision in _hook_output, or says why not and
# returns 1. Claude Code reads a hook's output as one JSON value, so anything before or
# after the decision makes it no decision at all.
_hook_read_decision() {
  if ! _hook_field=$(printf '%s' "$_hook_output" | jq -sej --arg field "$1" '
    select(length == 1)
    | .[0].hookSpecificOutput
    | select(.hookEventName == "PreToolUse"
        and (.permissionDecisionReason | type == "string")
        and (.permissionDecision == "deny" or .permissionDecision == "ask"))
    | .[$field]' 2>/dev/null); then
    printf 'hook: the hook printed something other than a decision: %s\n' "$_hook_output" >&2
    return 1
  fi
}

# decision_of <script> <json>: prints deny, ask or none. Prints nothing and fails if
# the hook failed or printed anything but a complete decision.
decision_of() {
  _hook_run "$1" "$2" || return 1
  if [ -z "$_hook_output" ]; then
    echo none
    return 0
  fi
  _hook_read_decision permissionDecision || return 1
  printf '%s\n' "$_hook_field"
}

# reason_of <script> <json>: prints the reason the hook gave, and nothing if it made no
# decision. Fails like decision_of.
reason_of() {
  _hook_run "$1" "$2" || return 1
  [ -n "$_hook_output" ] || return 0
  _hook_read_decision permissionDecisionReason || return 1
  printf '%s' "$_hook_field"
}

# assert_decision <deny|ask|none> <script> <json>
assert_decision() {
  if ! _hook_decision=$(decision_of "$2" "$3"); then
    _assert_fail "expected $1, got no readable decision for: $3"
  fi
  [ "$_hook_decision" = "$1" ] || _assert_fail "expected $1, got \"$_hook_decision\" for: $3"
}
