#!/bin/sh
# The attribution rule for text bound for GitHub, for the hooks that have sourced the git
# hooks' library and exported LC_ALL=C. Source this file; don't run it.

# The text as GitHub would show it. People and tools write \n in a body and mean a line.
readable_text() {
  printf '%s\n' "$1" | tr '\037' '\n' | sed 's/\\n/\
/g'
}

# deny_attribution <text>: ends the script with a denial if the text credits an AI tool, or
# if that can't be checked.
deny_attribution() {
  # shellcheck disable=SC2119 # With no file, it reads stdin.
  readable_text "$1" | dw_has_attribution
  case $? in
    0) dw_deny "dev-workflow: AI attribution isn't allowed on GitHub: remove the line that credits the tool, or reword it." ;;
    1) ;;
    *) dw_deny "dev-workflow: could not check this text for AI attribution." ;;
  esac
}
