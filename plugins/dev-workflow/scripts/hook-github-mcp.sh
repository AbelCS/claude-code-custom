#!/bin/sh
# Runs before each GitHub MCP tool call. Blocks AI attribution in anything that isn't a
# plain read, and a merge that isn't a squash with no default message.
#
# The server is remote, so its tools can change at any time. This goes by the shape of a
# tool's name rather than a list, and takes a name it doesn't recognise as one that writes.
# Prefixes differ by how the server is installed, so a name counts from its last __.

# Nothing outside the shell before the gate: see common.sh.
case $0 in
  */*) scripts_dir=${0%/*} ;;
  *) scripts_dir=. ;;
esac
# shellcheck source=plugins/dev-workflow/scripts/lib/common.sh
. "$scripts_dir/lib/common.sh"
dw_gate

# Bytes, so that text in any encoding matches the same way.
LC_ALL=C
export LC_ALL

tool=$(dw_input '.tool_name | strings' 2>/dev/null) ||
  dw_deny "dev-workflow: couldn't read the tool's name in the hook input."
tool=${tool##*__}
case $tool in
  get_* | list_* | search_* | *_read) exit 0 ;;
esac

dw_source_git_lib "$scripts_dir"
# shellcheck source=plugins/dev-workflow/scripts/lib/attribution.sh
. "$scripts_dir/lib/attribution.sh"

# Each on its own line, as a trailer has to start one.
text=$(dw_input '[.tool_input | .. | strings] | join("\n")' 2>/dev/null) ||
  dw_deny "dev-workflow: couldn't read this tool's fields to check them."
deny_attribution "$text"

case $tool in
  *merge*pull_request* | *pull_request*merge*)
    squash=$(dw_input '.tool_input | objects | .merge_method == "squash" and (.commit_message == null or .commit_message == "")' 2>/dev/null)
    [ "$squash" = true ] ||
      dw_deny "dev-workflow: merge with merge_method \"squash\" and no commit_message, so the commit has the pull request's title and no default message."
    ;;
esac
