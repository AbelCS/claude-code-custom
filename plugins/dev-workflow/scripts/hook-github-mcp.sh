#!/bin/sh
# Runs before each GitHub MCP tool call. Blocks every merge tool, and AI attribution in
# anything else that isn't a plain read.
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
  # The server hands commit_message to go-github's Merge, which drops an empty one unless
  # DontDefaultIfBlank is set, so GitHub uses its default message. No fields can avoid that.
  *merge*pull_request* | *pull_request*merge*)
    dw_deny "dev-workflow: merge with gh pr merge <n> --squash --subject \"<title>\" --body \"\" --delete-branch instead. This tool can't blank the commit message: it drops an empty one, and GitHub then uses its default message."
    ;;
esac

dw_source_git_lib "$scripts_dir"
# shellcheck source=plugins/dev-workflow/scripts/lib/attribution.sh
. "$scripts_dir/lib/attribution.sh"

# Each on its own line, as a trailer has to start one.
text=$(dw_input '[.tool_input | .. | strings] | join("\n")' 2>/dev/null) ||
  dw_deny "dev-workflow: couldn't read this tool's fields to check them."
deny_attribution "$text"
