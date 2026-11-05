#!/bin/sh
# Runs before each Write and Edit. A workflow gaining a per-PR CI trigger needs a person's
# yes, as CI runs only for releases. It's the rule pre-commit applies to a staged workflow,
# with the same detector and the same idea of what a workflow is, except that this compares
# with the file on disk, where pre-commit compares with HEAD.

# Nothing outside the shell before the gate: see common.sh.
case $0 in
  */*) scripts_dir=${0%/*} ;;
  *) scripts_dir=. ;;
esac
# shellcheck source=plugins/dev-workflow/scripts/lib/common.sh
. "$scripts_dir/lib/common.sh"
dw_gate

# Words of a path are split by hand, and never expanded as file patterns.
LC_ALL=C
export LC_ALL
set -f

# Sets full_path to where a path from the tool leads: from the session's folder if it's
# relative, without . and .., and with links in the folders that exist followed.
find_full_path() {
  case $1 in
    /*) fp_path=$1 ;;
    *)
      dw_session_folder
      fp_path=$DW_SESSION_FOLDER/$1
      ;;
  esac

  fp_clean=
  IFS=/
  # shellcheck disable=SC2086 # Splitting on / is the point, and set -f is on.
  set -- $fp_path
  unset IFS
  for fp_part in "$@"; do
    case $fp_part in
      '' | .) ;;
      ..) fp_clean=${fp_clean%/*} ;;
      *) fp_clean=$fp_clean/$fp_part ;;
    esac
  done

  fp_folder=${fp_clean%/*}
  fp_rest=/${fp_clean##*/}
  while [ -n "$fp_folder" ] && [ ! -d "$fp_folder" ]; do
    fp_rest=/${fp_folder##*/}$fp_rest
    fp_folder=${fp_folder%/*}
  done
  if [ -n "$fp_folder" ] && fp_real=$(cd -P -- "$fp_folder" 2>/dev/null && pwd -P); then
    fp_folder=${fp_real%/}
  fi
  full_path=$fp_folder$fp_rest
}

tool=$(dw_input '.tool_name | strings' 2>/dev/null) ||
  dw_deny "dev-workflow: couldn't read the tool's name in the hook input."
case $tool in
  Write | Edit) ;;
  *) exit 0 ;;
esac
file=$(dw_input '.tool_input.file_path | strings' 2>/dev/null) ||
  dw_deny "dev-workflow: couldn't read the file's path in the hook input."
[ -n "$file" ] || exit 0

find_full_path "$file"
case $full_path in
  */.github/workflows/*) ;;
  *) exit 0 ;;
esac

# Each repo has its own workflows and its own list, as a worktree can differ from the
# project. A repo that isn't a project is none of this hook's business.
repo_root=${full_path%/.github/workflows/*}
relative=.github/workflows/${full_path##*/.github/workflows/}
_dw_exists "$repo_root/.claude/dev-workflow.json" || exit 0

dw_source_git_lib "$scripts_dir"
dw_is_workflow "$relative" || exit 0

DW_PROJECT_FILE=$repo_root/.claude/dev-workflow.json
allowlist=$(dw_project '(.ciAllowlist // []) | if type == "array" then .[] | strings else error("not a list") end' 2>/dev/null) ||
  dw_deny "dev-workflow: couldn't read ciAllowlist in $DW_PROJECT_FILE: it has to be a list of paths. Fix it, or run the setup skill to create it again."
dw_in_lines "$relative" "$allowlist" && exit 0

# What can't be followed needs the yes: it could be doing anything to the triggers.
cannot_tell() {
  dw_ask "dev-workflow: can't tell what this does to the triggers of $relative, so it needs a person's yes. CI runs only for releases."
}

before=
disk=/dev/null
if _dw_exists "$full_path"; then
  { [ -f "$full_path" ] && [ -r "$full_path" ]; } || cannot_tell
  before=$(cat -- "$full_path") || cannot_tell
  disk=$full_path
fi

# The file as the tool would leave it. The strings are plain text, not patterns. An empty
# old_string is how Edit creates a file, and it won't apply one to a file with text in it.
if [ "$tool" = Write ]; then
  after=$(dw_input '.tool_input.content | if type == "string" then . else error("no content") end' 2>/dev/null) || cannot_tell
else
  # shellcheck disable=SC2016 # The dollars are jq's.
  after=$(printf '%s' "$DW_INPUT" | jq -r --rawfile disk "$disk" '
    .tool_input
    | if (.old_string | type) != "string" or (.new_string | type) != "string" then error("no strings") else . end
    | .old_string as $old
    | .new_string as $new
    | if $old == "" then
        if $disk == "" then $new else error("the file has text") end
      elif ($disk | contains($old)) | not then
        error("not in the file")
      elif .replace_all == true then
        $disk | split($old) | join($new)
      else
        ($disk | split($old)) as $parts
        | $parts[0] + $new + ($parts[1:] | join($old))
      end
  ' 2>/dev/null) || cannot_tell
fi

cannot_read="dev-workflow: can't read the triggers of $relative as it would be, so it needs a person's yes: list them plainly under on:, without YAML aliases, anchors, tags or block scalars."
triggers=$(dw_ci_triggers "$after") || dw_ask "$cannot_read"
dw_in_lines '?' "$triggers" && dw_ask "$cannot_read"
[ -n "$triggers" ] || exit 0

# A copy this can't read vouches for nothing.
known=$(dw_ci_triggers "$before") || known=
dw_in_lines '?' "$known" && known=

# A shell that can't create the heredoc's temp file doesn't run the loop and carries on, so
# loop_ran tells that apart from gaining nothing.
gained=
loop_ran=
while IFS= read -r trigger; do
  loop_ran=1
  dw_in_lines "$trigger" "$known" || gained="$gained${gained:+, }$trigger"
done <<TRIGGERS
$triggers
TRIGGERS
[ -n "$loop_ran" ] || dw_deny "dev-workflow: the shell couldn't compare the triggers of $relative, so this can't be checked. It may have no folder it can write temp files to."
[ -z "$gained" ] ||
  dw_ask "dev-workflow: this gives $relative a trigger on $gained, and CI runs only for releases, so it needs a person's yes. Use workflow_dispatch, or add the file to ciAllowlist in .claude/dev-workflow.json and run the setup skill."
