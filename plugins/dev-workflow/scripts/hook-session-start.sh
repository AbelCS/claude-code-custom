#!/bin/sh
# Runs when a session starts. Says what's wrong with this project's setup, one line each:
# git hooks not active, a tool or plugin missing, a project file older than the plugin,
# maintenance overdue. Claude reads what this prints. Silent when all is well.
#
# It must not get in the session's way. So it always exits 0, what it can't work out
# becomes a line rather than an error, and it reads files rather than starting anything
# slow. That's why gh is only looked for, not asked whether it's signed in.
#
# Claude reads this output as context, and a repo's files and settings are the repo's to
# write. So a line never repeats a value from them: only fixed text, the plugin's own
# version, and numbers worked out here.

# Nothing outside the shell before the project file is found: see common.sh.
case $0 in
  */*) scripts_dir=${0%/*} ;;
  *) scripts_dir=. ;;
esac
[ -r "$scripts_dir/lib/common.sh" ] || exit 0
# shellcheck source=plugins/dev-workflow/scripts/lib/common.sh
. "$scripts_dir/lib/common.sh"

DW_PROJECT_DIR=
_dw_find_project "${CLAUDE_PROJECT_DIR:-$PWD}" || exit 0
DW_PROJECT_FILE=$DW_PROJECT_DIR/.claude/dev-workflow.json
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE

say() {
  printf 'dev-workflow: %s\n' "$1"
}

have() {
  command -v "$1" >/dev/null 2>&1
}

check_tools() {
  have git || say "git isn't on the PATH. Install it: brew install git, or apt-get install git."
  have gh || say "gh isn't on the PATH. Install it: brew install gh, or see https://cli.github.com."
  have jq || say "jq isn't on the PATH, and this project's checks need it. Install it: brew install jq, or apt-get install jq."
}

# --- Git hooks

# What each hook tool leaves in the hooks it writes to git's own folder. Other tools work
# through core.hooksPath.
known_hook_tools='lefthook|husky|pre-commit\.com|simple_git_hooks|overcommit'

# Sets session_folder to the session's own worktree when it's in one, as a project variable
# can name the main checkout, and hooks_folder to where git looks for hooks there. Returns
# 1 if this isn't a repo yet, which leaves no hooks to turn on.
find_git_folders() {
  have git || return 1
  for session_folder in "$PWD" "$DW_PROJECT_DIR"; do
    if hooks_folder=$(git -C "$session_folder" rev-parse --git-path hooks 2>/dev/null); then
      case $hooks_folder in
        /*) ;;
        *) hooks_folder=$session_folder/$hooks_folder ;;
      esac
      return 0
    fi
  done
  return 1
}

# Whether core.hooksPath, which has a value, leads to hooks. A value can be left over or set
# for every repo, so what counts is whether pre-push is there. A copy may have lost the
# mode, so it needn't be executable. Git reads a relative path from the top of the worktree.
hooks_path_has_hooks() {
  case $1 in
    /*) hp_folder=$1 ;;
    *)
      hp_top=$(git -C "$session_folder" rev-parse --show-toplevel 2>/dev/null) || return 1
      hp_folder=$hp_top/$1
      ;;
  esac
  [ -f "$hp_folder/pre-push" ]
}

known_tool_hook_there() {
  for hook_name in commit-msg pre-commit pre-push; do
    if [ -f "$hooks_folder/$hook_name" ] && [ -x "$hooks_folder/$hook_name" ] &&
      grep -Eiq "$known_hook_tools" "$hooks_folder/$hook_name" 2>/dev/null; then
      return 0
    fi
  done
  return 1
}

check_git_hooks() {
  find_git_folders || return 0
  # --path reads ~ as git does.
  hooks_path=$(git -C "$session_folder" config --path --get core.hooksPath 2>/dev/null)
  if [ -n "$hooks_path" ]; then
    hooks_path_has_hooks "$hooks_path" && return 0
  else
    known_tool_hook_there && return 0
  fi
  say "git hooks aren't active here, so nothing checks commits or pushes. Turn them on: git config core.hooksPath .githooks (if there's no .githooks folder, run /dev-workflow:setup)."
}

# --- The project file against the plugin

# Sets version_parts to the three numbers of a version, ignoring a pre-release or build
# part, with missing numbers as 0. Returns 1 if it isn't a version, which includes numbers
# too long for the shell to compare.
read_version() {
  rv_numbers=${1%%[-+]*}
  case $rv_numbers in
    '' | .* | *. | *..* | *[!0-9.]* | *[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]*) return 1 ;;
  esac
  rv_ifs=$IFS
  IFS=.
  # shellcheck disable=SC2086 # Split on the dots.
  set -- $rv_numbers 0 0
  IFS=$rv_ifs
  version_parts="$1 $2 $3"
}

# version_is_older <a> <b>: both already through read_version, as "1 2 3".
version_is_older() {
  # shellcheck disable=SC2086 # Three numbers.
  set -- $1 $2
  # By test rather than arithmetic, which would read a leading zero as octal.
  [ "$1" -lt "$4" ] && return 0
  [ "$1" -gt "$4" ] && return 1
  [ "$2" -lt "$5" ] && return 0
  [ "$2" -gt "$5" ] && return 1
  [ "$3" -lt "$6" ]
}

check_plugin_version() {
  plugin_version=$(jq -r '.version | strings' "$scripts_dir/../.claude-plugin/plugin.json" 2>/dev/null)
  read_version "$plugin_version" || return 0
  plugin_parts=$version_parts

  project_version=$(dw_project '.pluginVersion | strings' 2>/dev/null)
  if [ -z "$project_version" ]; then
    say ".claude/dev-workflow.json has no pluginVersion, so its setup can't be compared with the plugin's $plugin_version. Run /dev-workflow:setup."
  elif ! read_version "$project_version"; then
    say ".claude/dev-workflow.json has a pluginVersion that isn't a version. Run /dev-workflow:setup."
  elif version_is_older "$version_parts" "$plugin_parts"; then
    say "this project was set up with an older version of the plugin, and $plugin_version is installed. Run /dev-workflow:setup to upgrade it."
  fi
}

# --- Plugins

# need_plugin <name> <install command>
need_plugin() {
  case "$_dw_newline$installed_plugins$_dw_newline" in
    *"$_dw_newline$1$_dw_newline"*) ;;
    *) say "the $1 plugin isn't installed. Install it: $2" ;;
  esac
}

# The folder a plugin installed for this project was recorded under, which in a worktree
# is the main checkout.
main_checkout() {
  have git || return 0
  mc_common=$(git -C "$DW_PROJECT_DIR" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 0
  printf '%s\n' "${mc_common%/.git}"
}

check_plugins() {
  registry=${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/installed_plugins.json
  installed_plugins=
  if [ -e "$registry" ]; then
    # A plugin installed for a project is only there for that project.
    if ! _dw_is_one_object "$registry" ||
      ! installed_plugins=$(jq -re --arg here "$DW_PROJECT_DIR" --arg main "$(main_checkout)" '
        .plugins | to_entries | map(
          select(.value | any(
            (.scope != "project" and .scope != "local")
            or .projectPath == $here or .projectPath == $main))
          | .key | split("@")[0]) | join("\n")' "$registry" 2>/dev/null); then
      say "couldn't read installed_plugins.json, so the plugins this project relies on weren't checked."
      return 0
    fi
  fi

  official='claude plugin install'
  need_plugin superpowers "$official superpowers@claude-plugins-official"
  need_plugin context7 "$official context7@claude-plugins-official"
  need_plugin serena "$official serena@claude-plugins-official"
  [ "$(dw_project '.hasScreens == true' 2>/dev/null)" = true ] || return 0
  need_plugin intent "claude plugin marketplace add ghaida/intent, then $official intent@intent"
  need_plugin ui-ux-pro-max "claude plugin marketplace add nextlevelbuilder/ui-ux-pro-max-skill, then $official ui-ux-pro-max@ui-ux-pro-max-skill"
}

# --- Maintenance

# Sets interval to the setting if it's a whole number of days from 1 up, and to 30 if not.
read_interval() {
  interval=${CLAUDE_PLUGIN_OPTION_MAINTENANCE_INTERVAL_DAYS:-}
  while :; do
    case $interval in
      0?*) interval=${interval#0} ;;
      *) break ;;
    esac
  done
  case $interval in
    '' | 0 | *[!0-9]* | ???????*) interval=30 ;;
  esac
}

# Sets date_days to the date's number of days from a fixed day, or returns 1 if it isn't a
# real date from year 1000 on. This is arithmetic rather than date -d or date -j, which
# differ between GNU and macOS. It's the usual count of days in the civil calendar, with
# March as the first month, so that a leap day falls at the end of the year.
read_date() {
  case $1 in
    [1-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
    *) return 1 ;;
  esac
  rd_year=${1%%-*}
  rd_rest=${1#*-}
  # One leading zero off each, since arithmetic would read it as octal.
  rd_month=${rd_rest%-*}
  rd_month=${rd_month#0}
  rd_day=${rd_rest#*-}
  rd_day=${rd_day#0}

  case $rd_month in
    1 | 3 | 5 | 7 | 8 | 10 | 12) rd_last=31 ;;
    4 | 6 | 9 | 11) rd_last=30 ;;
    2)
      if [ $((rd_year % 4)) -eq 0 ] && { [ $((rd_year % 100)) -ne 0 ] || [ $((rd_year % 400)) -eq 0 ]; }; then
        rd_last=29
      else
        rd_last=28
      fi
      ;;
    *) return 1 ;;
  esac
  [ "$rd_day" -ge 1 ] && [ "$rd_day" -le "$rd_last" ] || return 1

  [ "$rd_month" -gt 2 ] || rd_year=$((rd_year - 1))
  date_days=$((rd_year * 365 + rd_year / 4 - rd_year / 100 + rd_year / 400 + (153 * ((rd_month + 9) % 12) + 2) / 5 + rd_day))
}

# Sets last_entry to the text of the last run in the log, and returns 1 if it has none. A
# run is a list item, or a line that starts with what could be a date.
read_last_entry() {
  rl_found=1
  last_entry=
  while IFS= read -r rl_line || [ -n "$rl_line" ]; do
    case $rl_line in
      '- '* | '* '*)
        last_entry=${rl_line#??}
        rl_found=0
        ;;
      [0-9][0-9][0-9][0-9]-*)
        last_entry=$rl_line
        rl_found=0
        ;;
    esac
  done <"$1"
  return "$rl_found"
}

check_maintenance() {
  log=$DW_PROJECT_DIR/docs/maintenance.md
  [ -e "$log" ] || return 0
  cant_read="couldn't read docs/maintenance.md: its last line should be a list item like \"- YYYY-MM-DD: what was done\"."
  if [ ! -f "$log" ] || [ ! -r "$log" ]; then
    say "$cant_read"
    return 0
  fi

  read_last_entry "$log" || return 0

  last_date=${last_entry%%[!0-9-]*}
  case ${last_entry#"$last_date"} in
    '' | :* | ' '*) ;;
    *) last_date= ;;
  esac
  if ! read_date "$last_date"; then
    say "$cant_read"
    return 0
  fi
  last_days=$date_days

  today=$(date +%Y-%m-%d 2>/dev/null)
  if ! read_date "$today"; then
    say "couldn't work out today's date, so the last run in docs/maintenance.md wasn't checked."
    return 0
  fi

  read_interval
  age=$((date_days - last_days))
  [ "$age" -gt "$interval" ] &&
    say "maintenance is overdue: the last run was $age days ago, and it's due every $interval days. Run /dev-workflow:maintain."
}

check_tools
check_git_hooks
if have jq; then
  if _dw_is_one_object "$DW_PROJECT_FILE"; then
    check_plugin_version
    check_plugins
  else
    say ".claude/dev-workflow.json is broken: it must hold one valid JSON object. Fix it, or run /dev-workflow:setup to create it again."
  fi
fi
check_maintenance
exit 0
