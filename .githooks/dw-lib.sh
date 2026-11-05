#!/bin/sh
# Shared by the dev-workflow git hooks, and by the plugin's Claude Code hooks for the rules
# both layers apply: attribution, DW_SUBJECT and the CI triggers of a workflow. Source this
# file; don't run it.
#
# dev-workflow.env sits next to the hooks. Setup generates it from the project file:
#   DW_DEFAULT_BRANCH  the default branch
#   DW_CHECK           the check command
#   DW_CI_ALLOWLIST    newline-separated paths
#   DW_FORMATTERS      newline-separated glob|command lines

DW_COMMIT_TYPES='feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert'

# The start of a Conventional Commits subject, as an extended regular expression.
# shellcheck disable=SC2034 # For the scripts sourcing this.
DW_SUBJECT="($DW_COMMIT_TYPES)(\\([^)]+\\))?!?: [^ ]"

# AI tools and the vendors people name in their place. Some are ordinary words or
# people's names, which is why every pattern below needs them as a whole word.
DW_AI_TOOLS='claude|copilot|chatgpt|codex|gemini|cursor|aider|devin|anthropic|openai'
DW_AI_ADDRESSES='anthropic\.com|openai\.com|cursor\.com|cursor\.sh|aider\.chat|cognition\.ai|devin\.ai'

# Parts of the pattern. `not` is any byte that isn't a letter or digit, which marks
# word edges, since POSIX has no \b, and skips Markdown and emoji at a line's start.
_dw_not='[^[:alnum:]]'
_dw_space='[[:space:]]'
_dw_tool="($DW_AI_TOOLS)"
# Markdown around a trailer's parts, as in **Co-Authored-By:** Claude.
_dw_mark='[*_`]*'
_dw_coauthor="^$_dw_not*(co-authored|assisted)-by$_dw_mark$_dw_space*:$_dw_mark"
_dw_generated="(generated[-[:space:]]+(with|by)|written[-[:space:]]+by)"

# A co-author is an AI when the whole name is a tool's, perhaps with a version, or
# when the address or the GitHub account is. People can share a name with a tool, so
# a longer name with another address passes. Assisted-by can add :model to the name.
_dw_attribution="$_dw_coauthor$_dw_space*$_dw_mark((github|google|anthropic|openai)$_dw_space+)?$_dw_tool"
_dw_attribution="$_dw_attribution($_dw_space+(code|cli|agent|ai|assistant))*"
_dw_attribution="$_dw_attribution($_dw_space+([a-z]+$_dw_space+)?v?[0-9][0-9.]*)?(:[^[:space:]]*)?$_dw_mark$_dw_space*(<|\$)"
_dw_attribution="$_dw_attribution|$_dw_coauthor.*@([a-z0-9.-]+\\.)?($DW_AI_ADDRESSES)([^a-z0-9.-]|\$)"
_dw_attribution="$_dw_attribution|$_dw_coauthor.*<([0-9]+\\+)?$_dw_tool(\\[bot\\])?@users\\.noreply\\.github\\.com>"
_dw_attribution="$_dw_attribution|$_dw_coauthor(.*$_dw_not)?$_dw_tool($_dw_not.*)?\\[bot\\]"
# A line opening with "generated with" can name the tool anywhere. Further along a
# line the tool has to follow directly, so "lines generated with it" can name one later.
_dw_attribution="$_dw_attribution|^$_dw_not*$_dw_generated$_dw_not(.*$_dw_not)?$_dw_tool($_dw_not|\$)"
_dw_attribution="$_dw_attribution|(^|$_dw_not)$_dw_generated$_dw_not+((the|a|an|github|google|help|assistance|of|from)$_dw_not+)*$_dw_tool($_dw_not|\$)"
# The robot emoji footer, as bytes so that this file stays ASCII.
_dw_attribution="$_dw_attribution|^$_dw_not*$(printf '\360\237\244\226')"

# dw_has_attribution [file]: reads the file, or stdin with no argument, exactly as it is.
# An empty name is a file it can't read. It knows nothing of comments, so which lines count
# is up to the caller. Exits 0 if found, 1 if not, and above 1 if it
# couldn't read the text, which callers must not take as clean. It matches bytes, so the
# emoji works in any locale.
dw_has_attribution() {
  if [ "$#" -gt 0 ]; then
    LC_ALL=C grep -Eiq -e "$_dw_attribution" -- "$1"
  else
    LC_ALL=C grep -Eiq -e "$_dw_attribution"
  fi
}

# dw_issue_from_branch <branch>: prints the issue number of a <type>/<issue>-<slug>
# branch, and nothing for any other.
dw_issue_from_branch() {
  printf '%s\n' "$1" | sed -En "s#^($DW_COMMIT_TYPES)/([0-9]+)-.+\$#\\2#p"
}

# dw_in_lines <text> <lines>: whether one of the lines is exactly the text.
dw_in_lines() {
  case "
$2
" in
    *"
$1
"*) return 0 ;;
  esac
  return 1
}

# dw_is_workflow <path from the repo's root>: only these run, as GitHub ignores a workflow
# in a subfolder.
dw_is_workflow() {
  case $1 in
    .github/workflows/*/*) return 1 ;;
    .github/workflows/*.yml | .github/workflows/*.yaml) return 0 ;;
  esac
  return 1
}

# Reads a workflow on stdin, and prints each per-PR trigger under its top-level `on:`,
# one per line, with ? last if it can't tell. There's no YAML parser to hand, so this
# follows only the structure of `on:`: a scalar, a block map or sequence whose direct
# children are read and deeper lines ignored, or a flow map or sequence that runs until its
# brackets close, at any indent. An alias, block scalar, merge, complex key, anchor or tag
# could hide a trigger, as could a file that's one flow map, so those are the ? case.
# shellcheck disable=SC2016 # The dollars are awk's.
_dw_ci_trigger_program='
  function strip(line,    i, c, before, quote) {
    sub(/\r$/, "", line)
    for (i = 1; i <= length(line); i++) {
      c = substr(line, i, 1)
      before = i > 1 ? substr(line, i - 1, 1) : " "
      if (quote == "\"" && c == "\\") i++
      else if (quote != "") { if (c == quote) quote = "" }
      else if ((c == "\"" || c == "\047") && before ~ /[ \t[{,:]/) quote = c
      else if (c == "#" && before ~ /[ \t]/) { line = substr(line, 1, i - 1); break }
    }
    sub(/[ \t]+$/, "", line)
    return line
  }

  function unreadable() {
    print "?"
    exit
  }

  function check(item) {
    sub(/^[ \t]+/, "", item)
    if (item ~ /^([*|>?&!]|<<)/) unreadable()
    if (match(item, /^"([^"\\]|\\.)*"/) || match(item, /^\047([^\047]|\047\047)*\047/)) {
      item = substr(item, 2, RLENGTH - 2)
    } else {
      if (match(item, /:([ \t]|$)/)) item = substr(item, 1, RSTART - 1)
      sub(/[ \t]+$/, "", item)
    }
    if (item == "push" || item == "pull_request" || item == "pull_request_target") {
      if (!(item in seen)) print item
      seen[item] = 1
    }
  }

  function flow(text,    i, c, before) {
    for (i = 1; i <= length(text); i++) {
      c = substr(text, i, 1)
      before = i > 1 ? substr(text, i - 1, 1) : " "
      if (flow_quote != "") {
        if (depth == 1) flow_item = flow_item c
        if (flow_quote == "\"" && c == "\\") {
          i++
          if (depth == 1) flow_item = flow_item substr(text, i, 1)
        } else if (c == flow_quote) flow_quote = ""
      } else if (c == "[" || c == "{") depth++
      else if (c == "]" || c == "}") {
        if (depth == 1) { check(flow_item); flow_item = "" }
        if (--depth == 0) { state = "seek"; return }
      } else if (depth == 1 && c == ",") { check(flow_item); flow_item = "" }
      else {
        if ((c == "\"" || c == "\047") && before ~ /[ \t[{,:]/) flow_quote = c
        if (depth == 1) flow_item = flow_item c
      }
    }
    flow_item = flow_item " "
  }

  function start_flow(text) {
    state = "flow"
    depth = 0
    flow_quote = flow_item = ""
    flow(text)
  }

  BEGIN { state = "seek"; top = -1 }

  NR == 1 { sub(/^\357\273\277/, "") }

  {
    line = strip($0)
    text = line
    sub(/^ +/, "", text)
    if (text == "") next
    indent = length(line) - length(text)

    if (state == "flow") { flow(line); next }

    if (state == "first") {
      if (indent < on_indent || (indent == on_indent && text !~ /^-([ \t]|$)/)) state = "seek"
      else if (text ~ /^[[{]/) { start_flow(text); next }
      else {
        state = "children"
        child_indent = indent
        in_sequence = text ~ /^-([ \t]|$)/
      }
    }

    if (state == "children") {
      if (indent > child_indent) {
        # A lone - has its value on the next line.
        if (value_due) { value_due = 0; check(text) }
        next
      }
      value_due = 0
      if (indent == child_indent && !in_sequence) { check(text); next }
      if (indent == child_indent && text ~ /^-([ \t]|$)/) {
        sub(/^-[ \t]*/, "", text)
        if (text == "") value_due = 1
        else check(text)
        next
      }
      state = "seek"
    }

    if (text ~ /^---$|^%/) next
    if (top < 0) {
      top = indent
      if (text ~ /^(---[ \t]+)?\{/) unreadable()
    }
    if (indent != top || text !~ /^(on[ \t]*:([ \t]|$)|("on"|\047on\047)[ \t]*:)/) next

    sub(/^[^:]*:[ \t]*/, "", text)
    if (text == "") { state = "first"; on_indent = indent }
    else if (text ~ /^[[{]/) start_flow(text)
    else check(text)
  }
'

# dw_ci_triggers <workflow text>: prints what the program above finds. A failure here isn't
# a clean file, so a caller must act on it.
dw_ci_triggers() {
  printf '%s\n' "$1" | LC_ALL=C awk "$_dw_ci_trigger_program"
}

# dw_run_local <hook> [args...]: runs <hook>.local next to the running hook, if it's
# there, with the same arguments and stdin: a hook setup moved here from .git/hooks,
# which runs first. Returns its status, for the hook to stop on. One that isn't
# executable is skipped, as git would skip it, with a word.
dw_run_local() {
  _dw_local="$(dirname "$0")/$1.local"
  shift
  [ -e "$_dw_local" ] || return 0
  if [ ! -x "$_dw_local" ]; then
    printf "dev-workflow: %s isn't executable, so it was skipped\n" "$_dw_local" >&2
    return 0
  fi
  "$_dw_local" "$@"
}

# dw_load_env: sources dev-workflow.env next to the running hook. Prints why and
# returns 1 if it's missing or broken. It returns rather than exits so that each hook
# decides what that means for it.
dw_load_env() {
  _dw_env="$(dirname "$0")/dev-workflow.env"
  if [ ! -r "$_dw_env" ]; then
    printf 'dev-workflow: %s is missing: run the setup skill to create it\n' "$_dw_env" >&2
    return 1
  fi
  # A syntax error in a sourced file would end the hook with no useful message.
  if ! sh -n "$_dw_env" 2>/dev/null; then
    printf 'dev-workflow: %s is broken: run the setup skill to create it again\n' "$_dw_env" >&2
    return 1
  fi
  # shellcheck source=/dev/null
  . "$_dw_env"
}
