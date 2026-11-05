#!/bin/sh
# Shared by the plugin's Claude Code hook scripts. Source this file; don't run it.
#
# A hook decides by what it prints, then exits 0: printing nothing means no decision.
# dw_deny and dw_ask end the script, so don't call them inside a command substitution,
# where they would end only the substitution and their output would be lost.
#
# Hooks must do nothing in a project without the project file, and such a project may
# not have jq. So dw_gate looks for that file with the shell alone, and a hook should
# run nothing before dw_gate. Only without CLAUDE_PROJECT_DIR does the search itself
# use jq, if it's there, to read cwd from the hook input.

_dw_newline='
'
_dw_tab='	'

# Sets _dw_escaped to <text> as the inside of a JSON string, using only the shell,
# because the denial for a missing jq has to work too. Bytes above ASCII pass through.
_dw_json_escape() {
  _dw_rest=$1
  _dw_escaped=
  while [ -n "$_dw_rest" ]; do
    _dw_after=${_dw_rest#?}
    _dw_char=${_dw_rest%"$_dw_after"}
    _dw_rest=$_dw_after
    # shellcheck disable=SC1003 # These backslashes are JSON's.
    case $_dw_char in
      \\) _dw_char='\\' ;;
      \") _dw_char='\"' ;;
      "$_dw_newline") _dw_char='\n' ;;
      "$_dw_tab") _dw_char='\t' ;;
      [[:cntrl:]]) _dw_char=$(printf '\\u%04x' "'$_dw_char") ;;
    esac
    _dw_escaped=$_dw_escaped$_dw_char
  done
}

_dw_decide() {
  _dw_json_escape "$2"
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"%s","permissionDecisionReason":"%s"}}\n' \
    "$1" "$_dw_escaped"
  exit 0
}

# dw_deny <reason>: blocks the tool call and ends the script.
dw_deny() {
  _dw_decide deny "$1"
}

# dw_ask <reason>: makes the tool call need a person's yes and ends the script.
dw_ask() {
  _dw_decide ask "$1"
}

# A dangling link counts as there: a project file shows the project is set up, and is
# then denied as broken rather than letting everything through.
_dw_exists() {
  [ -e "$1" ] || [ -L "$1" ]
}

# Sets DW_PROJECT_DIR to the nearest directory with a project file, from <dir> upward,
# since a session can run from a subfolder. Returns 1 if there is none. The first .git,
# a folder or a worktree's file, is the repo's root and the last place to look, so a
# nested repo doesn't take its parent's project file. Uses the shell alone.
_dw_find_project() {
  _dw_dir=$1
  while :; do
    if _dw_exists "$_dw_dir/.claude/dev-workflow.json"; then
      DW_PROJECT_DIR=${_dw_dir:-/}
      return 0
    fi
    _dw_exists "$_dw_dir/.git" && return 1
    # The root is the empty string here, and a relative path ends at its first name.
    case $_dw_dir in
      */*) _dw_dir=${_dw_dir%/*} ;;
      *) return 1 ;;
    esac
  done
}

# The same from the input's cwd, which has to be a full path.
_dw_project_from_cwd() {
  _dw_cwd=$(printf '%s' "$DW_INPUT" | jq -r '.cwd | strings' 2>/dev/null) || return 1
  case $_dw_cwd in
    /*) _dw_find_project "$_dw_cwd" ;;
    *) return 1 ;;
  esac
}

# Reads stdin, or the file named, and succeeds on exactly one JSON object. An empty file
# and several values are not errors to jq on their own.
_dw_is_one_object() {
  jq -se 'length == 1 and (.[0] | type == "object")' ${1:+"$1"} >/dev/null 2>&1
}

# dw_gate: the first thing a hook does. Ends the script with no decision unless this
# is a project with a project file. Denies if that project can't be checked. Otherwise
# returns with these set:
#   DW_PROJECT_DIR   the project's root
#   DW_PROJECT_FILE  its project file
#   DW_INPUT         the hook input, which this has read from stdin
dw_gate() {
  DW_PROJECT_DIR=
  if [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
    _dw_find_project "$CLAUDE_PROJECT_DIR" || exit 0
  fi

  if ! command -v jq >/dev/null 2>&1; then
    # Finding the project without the variable means reading cwd, which takes jq.
    [ -n "$DW_PROJECT_DIR" ] || exit 0
    dw_deny "dev-workflow: this project's checks need jq, which isn't on the PATH. Install jq and try again."
  fi

  DW_INPUT=$(cat)
  if [ -z "$DW_PROJECT_DIR" ]; then
    _dw_project_from_cwd || exit 0
  fi

  DW_PROJECT_FILE=$DW_PROJECT_DIR/.claude/dev-workflow.json
  if ! _dw_is_one_object "$DW_PROJECT_FILE"; then
    dw_deny "dev-workflow: $DW_PROJECT_FILE is broken: it must hold one valid JSON object. Fix it, or run the setup skill to create it again."
  fi
  if ! printf '%s' "$DW_INPUT" | _dw_is_one_object; then
    dw_deny "dev-workflow: the hook input from Claude Code isn't a JSON object, so this can't be checked."
  fi
}

# dw_project <jq-filter>: prints the filter's result on the project file, with strings
# unquoted. Returns non-zero if it fails. For use after dw_gate; it doesn't deny, because
# it's usually called in a command substitution, so a caller must act on the failure.
dw_project() {
  jq -r "$1" "$DW_PROJECT_FILE"
}

# dw_input <jq-filter>: the same on the hook input.
dw_input() {
  printf '%s' "$DW_INPUT" | jq -r "$1"
}
