#!/bin/sh
# Shared by the dev-workflow git hooks, and by the plugin's Claude Code hooks for
# dw_has_attribution. Source this file; don't run it.
#
# dev-workflow.env sits next to the hooks. Setup generates it from the project file:
#   DW_DEFAULT_BRANCH  the default branch
#   DW_CHECK           the check command
#   DW_CI_ALLOWLIST    newline-separated paths
#   DW_FORMATTERS      newline-separated glob|command lines

DW_COMMIT_TYPES='feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert'

# AI tools and the vendors people name in their place. Some are ordinary words or
# people's names, which is why every pattern below needs them as a whole word.
DW_AI_TOOLS='claude|copilot|chatgpt|codex|gemini|cursor|aider|devin|anthropic|openai'
DW_AI_ADDRESSES='anthropic\.com|openai\.com|cursor\.com|cursor\.sh|aider\.chat|cognition\.ai|devin\.ai'

# Parts of the pattern. `not` is any byte that isn't a letter or digit, which marks
# word edges, since POSIX has no \b, and skips Markdown and emoji at a line's start.
_dw_not='[^[:alnum:]]'
_dw_space='[[:space:]]'
_dw_tool="($DW_AI_TOOLS)"
_dw_coauthor="^$_dw_not*co-authored-by$_dw_space*:"
_dw_generated="(generated[-[:space:]]+(with|by)|written[-[:space:]]+by)"

# A co-author is an AI when the whole name is a tool's, perhaps with a version, or
# when the address or the GitHub account is. People can share a name with a tool, so
# a longer name with another address passes.
_dw_attribution="$_dw_coauthor$_dw_space*((github|google|anthropic|openai)$_dw_space+)?$_dw_tool"
_dw_attribution="$_dw_attribution($_dw_space+(code|cli|agent|ai|assistant))*"
_dw_attribution="$_dw_attribution($_dw_space+([a-z]+$_dw_space+)?v?[0-9][0-9.]*)?$_dw_space*(<|\$)"
_dw_attribution="$_dw_attribution|$_dw_coauthor.*@([a-z0-9.-]+\\.)?($DW_AI_ADDRESSES)([^a-z0-9.-]|\$)"
_dw_attribution="$_dw_attribution|$_dw_coauthor.*<([0-9]+\\+)?$_dw_tool(\\[bot\\])?@users\\.noreply\\.github\\.com>"
_dw_attribution="$_dw_attribution|$_dw_coauthor(.*$_dw_not)?$_dw_tool($_dw_not.*)?\\[bot\\]"
# A line opening with "generated with" can name the tool anywhere. Further along a
# line the tool has to follow directly, so "lines generated with it" can name one later.
_dw_attribution="$_dw_attribution|^$_dw_not*$_dw_generated$_dw_not(.*$_dw_not)?$_dw_tool($_dw_not|\$)"
_dw_attribution="$_dw_attribution|(^|$_dw_not)$_dw_generated$_dw_not+((the|a|an|github|google|help|assistance|of|from)$_dw_not+)*$_dw_tool($_dw_not|\$)"
# The robot emoji footer, as bytes so that this file stays ASCII.
_dw_attribution="$_dw_attribution|^$_dw_not*$(printf '\360\237\244\226')"

# dw_has_attribution [file]: reads the file, or stdin without one, exactly as it is.
# Comments only exist in commit messages, so removing them is up to commit-msg.
# Exits 0 if found, 1 if not, and above 1 if it couldn't read the text, which callers
# must not take as clean. It matches bytes, so the emoji works in any locale.
dw_has_attribution() {
  LC_ALL=C grep -Eiq -e "$_dw_attribution" -- ${1:+"$1"}
}

# dw_issue_from_branch <branch>: prints the issue number of a <type>/<issue>-<slug>
# branch, and nothing for any other.
dw_issue_from_branch() {
  printf '%s\n' "$1" | sed -En "s#^($DW_COMMIT_TYPES)/([0-9]+)-.+\$#\\2#p"
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
