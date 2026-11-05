#!/bin/sh
# Runs before each Bash tool call. Reads what the command would run, not just its text,
# and blocks what the methodology rules out: skipping git hooks, merging locally into
# the default branch, merging after tests in one command, merging with a default message,
# bad pull request titles and bodies, and AI attribution on GitHub. A database reset
# needs a person's yes.
#
# Like the splitter it relies on, this catches mistakes rather than stopping anyone.

# Nothing outside the shell before the gate: see common.sh.
case $0 in
  */*) scripts_dir=${0%/*} ;;
  *) scripts_dir=. ;;
esac
# shellcheck source=plugins/dev-workflow/scripts/lib/common.sh
. "$scripts_dir/lib/common.sh"
dw_gate

# Bytes, so that text in any encoding matches the same way. Words of a command are split
# by hand, and never expanded as file patterns.
LC_ALL=C
export LC_ALL
set -f
unset GIT_DIR GIT_WORK_TREE

dw_lib=$scripts_dir/../skills/setup/templates/githooks/dw-lib.sh
[ -r "$dw_lib" ] || dw_deny "dev-workflow: $dw_lib is missing, so this command can't be checked. Reinstall the plugin."
# shellcheck source=plugins/dev-workflow/skills/setup/templates/githooks/dw-lib.sh
. "$dw_lib"

word_end=$(printf '\036')
line_in_word=$(printf '\037')
newline='
'

# shellcheck source=plugins/dev-workflow/scripts/lib/walk-flags.sh
. "$scripts_dir/lib/walk-flags.sh"
# shellcheck source=plugins/dev-workflow/scripts/lib/bash-rules-git.sh
. "$scripts_dir/lib/bash-rules-git.sh"
# shellcheck source=plugins/dev-workflow/scripts/lib/bash-rules-gh.sh
. "$scripts_dir/lib/bash-rules-gh.sh"

# --- Reading commands

# normal_commands <text>: prints each simple command in the text as its words, each ended
# by word_end. See command-words.awk. Fails if either step does.
normal_commands() {
  nc_split=$(printf '%s\n' "$1" | awk -v 'WORD_END=\036' -f "$scripts_dir/lib/split-command.awk" 2>/dev/null) || return 1
  printf '%s\n' "$nc_split" | DW_ROOT=$DW_PROJECT_DIR awk -f "$scripts_dir/lib/command-words.awk" 2>/dev/null
}

# project_commands <jq filter>: normal_commands of what the filter finds in the project
# file, with a list that isn't a list being an error.
project_commands() {
  pc_text=$(dw_project "def list(\$name): (.[\$name] // []) | if type == \"array\" then .[] else error(\"not a list\") end; $1 | strings" 2>/dev/null) || return 1
  [ -z "$pc_text" ] || normal_commands "$pc_text"
}

# matches_any <normal commands> <normal command>: whether the command starts with all
# the words of any on the list. Moving to a folder is part of how a project runs a
# command, not what it runs, so it doesn't count.
matches_any() {
  ma_rest=$1$newline
  while [ -n "$ma_rest" ]; do
    ma_pattern=${ma_rest%%"$newline"*}
    ma_rest=${ma_rest#*"$newline"}
    case $ma_pattern in
      '' | "cd$word_end"*) continue ;;
    esac
    case $2 in
      "$ma_pattern"*) return 0 ;;
    esac
  done
  return 1
}

# Sets session_folder to where the session's shell is, from the input, or else the
# project's folder. Commands run from there, and with worktrees it can be another branch.
find_session_folder() {
  session_folder=$(dw_input '.cwd | strings' 2>/dev/null)
  case $session_folder in
    /*) [ -d "$session_folder" ] || session_folder=$DW_PROJECT_DIR ;;
    *) session_folder=$DW_PROJECT_DIR ;;
  esac
}

# --- Database resets

# docker compose down with -v removes the volumes, wherever its options sit.
removes_compose_volumes() {
  case ${1-} in
    docker)
      [ "${2-}" = compose ] || return 1
      shift 2
      ;;
    docker-compose) shift ;;
    *) return 1 ;;
  esac
  while [ "$#" -gt 0 ] && [ "$1" != down ]; do
    case $1 in
      -f | --file | -p | --project-name | --profile | --env-file | --project-directory | --ansi | --parallel | --progress)
        [ "$#" -lt 2 ] || shift
        ;;
      -*) ;;
      *) return 1 ;;
    esac
    shift
  done
  for rc_word in "$@"; do
    case $rc_word in
      -v | --volumes | --volumes=true) return 0 ;;
    esac
  done
  return 1
}

# --- The command

check_tool() {
  case $1 in
    git)
      shift
      check_git "$@"
      ;;
    gh)
      shift
      check_gh "$@"
      ;;
  esac
}

command_text=$(dw_input '.tool_input.command // empty' 2>/dev/null) ||
  dw_deny "dev-workflow: couldn't read the command in the hook input."
[ -n "$command_text" ] || exit 0

broken_project="dev-workflow: couldn't read the lists in $DW_PROJECT_FILE: commands has to be an object, and testCommands and databaseResetCommands lists. Fix it, or run the setup skill to create it again."
test_commands=$(project_commands '.commands.check, .commands.verify, list("testCommands")') || dw_deny "$broken_project"
reset_commands=$(project_commands 'list("databaseResetCommands")') || dw_deny "$broken_project"
reset_commands="dropdb$word_end$newline$reset_commands"

commands=$(normal_commands "$command_text") || dw_deny "dev-workflow: couldn't read this command to check it."

test_seen=
ask_reason=
branch_moves=

# Not a pipeline: that would run the loop in a subshell, losing test_seen and leaving a
# denial to end only the loop.
while IFS= read -r line; do
  [ -n "$line" ] || continue
  IFS=$word_end
  # shellcheck disable=SC2086 # Splitting on word_end is the point, and set -f is on.
  set -- $line
  unset IFS

  merging=
  check_tool "$@"
  if [ -n "$merging" ] && [ -n "$test_seen" ]; then
    dw_deny "dev-workflow: this merges in the same command as a test. Run the tests, read the results, then merge in a command of its own."
  fi

  matches_any "$test_commands" "$line" && test_seen=1
  if matches_any "$reset_commands" "$line" || removes_compose_volumes "$@"; then
    ask_reason="dev-workflow: this looks like a database reset, which destroys data, so it needs a person's yes."
  fi
done <<COMMANDS
$commands
COMMANDS

# Last, so that a denial later in the command isn't lost behind an answer of yes.
[ -z "$ask_reason" ] || dw_ask "$ask_reason"
