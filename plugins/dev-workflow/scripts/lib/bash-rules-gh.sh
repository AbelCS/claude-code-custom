#!/bin/sh
# The rules on gh commands, for hook-bash.sh, which sets merging on a real merge and
# command_text to the raw command. Each check takes the words after gh and ends the
# script if it denies. Source this file; don't run it.
#
# shellcheck disable=SC2034,SC2154 # hook-bash.sh sets and reads these variables.

deny_bad_title() {
  case $1 in
    *"$newline"* | *"$line_in_word"*) ;;
    *) printf '%s\n' "$1" | grep -Eq "^$DW_SUBJECT" && return 0 ;;
  esac
  dw_deny "dev-workflow: a pull request title has to be one line and a Conventional Commit, like \"feat(scope): subject\"."
}

deny_no_closing_keyword() {
  readable_text "$1" | grep -Eiq '(^|[^[:alnum:]])(close[sd]?|fix(es|ed)?|resolve[sd]?):?[[:space:]]+([[:alnum:]_.-]+/[[:alnum:]_.-]+)?#[0-9]+' ||
    dw_deny "dev-workflow: a pull request body needs a closing keyword for its issue, like \"Closes #12\"."
}

# Adds a body file's text to gt_body. Standard input is settled once all flags are read.
read_body_file() {
  case $1 in
    -)
      gt_stdin=1
      return 0
      ;;
    # What's behind these isn't what gh would read, as this script has its own stdin.
    /dev/*) bf_path= ;;
    /*) bf_path=$1 ;;
    \~/*) bf_path=$HOME/${1#\~/} ;;
    *)
      dw_session_folder
      bf_path=$DW_SESSION_FOLDER/$1
      ;;
  esac
  if [ -f "$bf_path" ] && [ -r "$bf_path" ] && bf_text=$(cat -- "$bf_path"); then
    gt_body=$gt_body$newline$bf_text
  else
    dw_deny "dev-workflow: can't read the file $1 to check its text. Name a readable file, in full or from the session's current folder."
  fi
}

read_gh_text_flag() {
  case $1 in
    --title | -t)
      gt_title=$gt_title$newline${2-}
      gt_last_title=${2-}
      gt_has_title=1
      ;;
    --body | -b | --notes | -n | --comment | -c)
      gt_body=$gt_body$newline${2-}
      gt_has_body=1
      ;;
    --body-file | --notes-file | -F)
      gt_has_body=1
      read_body_file "${2-}"
      ;;
    --fill | --fill-first | --fill-verbose | -f) gt_fill=1 ;;
    --help | -h) gt_help=1 ;;
    '')
      case $2 in
        '<<'*) gt_inline_stdin=1 ;;
      esac
      ;;
  esac
}

# Settles standard input once all flags are read. A heredoc is in the raw command and in
# no word of it, so it joins the text. Anything else on stdin can't be seen from here.
settle_gh_stdin() {
  [ -n "$gt_stdin" ] || return 0
  [ -n "$gt_inline_stdin" ] || dw_deny "dev-workflow: can't read a body piped in on standard input to check it. Pass --body, a file, or a heredoc."
  gt_body=$gt_body$newline$command_text
}

# check_gh_text <action> <letters taking a value> <words...>: for each gh command that
# writes text for people to read. Flags are per command, as a letter means different
# things in different ones, and --comment takes text only on the close commands: on
# gh pr review it says what kind of review this is.
check_gh_text() {
  gt_action=$1
  gt_letters=$2
  shift 2
  gt_title=
  gt_last_title=
  gt_has_title=
  gt_body=
  gt_has_body=
  gt_fill=
  gt_help=
  gt_stdin=
  gt_inline_stdin=
  gt_long='--title --body --body-file --notes --notes-file --repo --base --head --assignee --add-assignee --remove-assignee --reviewer --add-reviewer --remove-reviewer --label --add-label --remove-label --project --add-project --remove-project --milestone --template --recover --target --discussion-category --notes-start-tag --type'
  case $gt_action in
    *' close') gt_long="$gt_long --comment --reason --duplicate-of" ;;
  esac
  walk_flags "$gt_long" "$gt_letters" '' read_gh_text_flag "$@"
  [ -z "$gt_help" ] || return 0

  if [ "$gt_action" = 'pr create' ] && [ -n "$gt_fill" ]; then
    dw_deny "dev-workflow: --fill takes the body from the commits, where the closing keyword can't be checked. Pass --title and --body instead."
  fi
  settle_gh_stdin

  # Text can reach a flag through a variable or a plain heredoc, so the raw command counts,
  # without the quotes that would close a variable's last line.
  deny_attribution "$gt_title$newline$gt_body"
  deny_attribution "$(printf '%s\n' "$command_text" | tr -d "\"'")"

  case $gt_action in
    'pr create')
      deny_bad_title "$gt_last_title"
      deny_no_closing_keyword "$gt_body"
      ;;
    'pr edit')
      [ -z "$gt_has_title" ] || deny_bad_title "$gt_last_title"
      [ -z "$gt_has_body" ] || deny_no_closing_keyword "$gt_body"
      ;;
  esac
}

# Notes what a gh api call would do, before anything is read for it.
note_gh_api_flag() {
  case $1 in
    --method | -X) ga_method=${2-} ;;
    --raw-field | -f | --field | -F | --input) ga_sends=1 ;;
    --help | -h) ga_help=1 ;;
  esac
}

read_gh_api_flag() {
  case $1 in
    --raw-field | -f) gt_body=$gt_body$newline${2#*=} ;;
    --field | -F)
      case ${2#*=} in
        @*) read_body_file "${2#*=@}" ;;
        *) gt_body=$gt_body$newline${2#*=} ;;
      esac
      ;;
    --input) read_body_file "${2-}" ;;
    '')
      case $2 in
        '<<'*) gt_inline_stdin=1 ;;
      esac
      ;;
  esac
}

# What gh api sends is mostly JSON, where a field's text doesn't start a line, so every
# quote ends one here. Without a named method, gh sends fields with POST.
check_gh_api() {
  ga_method=
  ga_sends=
  ga_help=
  ga_long='--method --field --raw-field --input --header --hostname --jq --template --preview --cache'
  walk_flags "$ga_long" XfFHqtp '' note_gh_api_flag "$@"
  [ -z "$ga_help" ] || return 0
  case $ga_method in
    [Gg][Ee][Tt] | [Hh][Ee][Aa][Dd]) return 0 ;;
    '') [ -n "$ga_sends" ] || return 0 ;;
  esac

  gt_body=
  gt_stdin=
  gt_inline_stdin=
  walk_flags "$ga_long" XfFHqtp '' read_gh_api_flag "$@"
  settle_gh_stdin
  deny_attribution "$(printf '%s\n%s\n' "$gt_body" "$command_text" | tr '"' '\n' | tr "'" '\n')"
}

read_gh_merge_flag() {
  case $1 in
    --squash | -s) gm_squash=1 ;;
    --merge | -m | --rebase | -r) gm_other=1 ;;
    --body | -b)
      gm_has_body=1
      gm_body=${2-}
      ;;
    --body-file | -F) gm_other=1 ;;
    --subject | -t) gm_subject=$gm_subject$newline${2-} ;;
    --disable-auto | --help | -h) gm_merges= ;;
  esac
}

check_gh_merge() {
  gm_merges=1
  gm_squash=
  gm_other=
  gm_has_body=
  gm_body=
  gm_subject=
  walk_flags '--subject --body --body-file --author-email --match-head-commit --repo' tbFAR '' read_gh_merge_flag "$@"
  [ -n "$gm_merges" ] || return 0
  merging=1
  if [ -z "$gm_squash" ] || [ -n "$gm_other" ] || [ -z "$gm_has_body" ] || [ -n "$gm_body" ]; then
    dw_deny "dev-workflow: merge with gh pr merge <number> --squash --subject \"<title>\" --body \"\" --delete-branch, so the commit has the pull request's title and no default message."
  fi
  deny_attribution "$gm_subject"
}

check_gh() {
  if [ "${1-}" = api ]; then
    shift
    check_gh_api "$@"
    return
  fi
  ch_group=${1-}
  ch_action=${2-}
  [ "$#" -lt 2 ] || shift 2
  case "$ch_group $ch_action" in
    'pr merge') check_gh_merge "$@" ;;
    'pr create') check_gh_text 'pr create' abBFHlmprtTR "$@" ;;
    'pr edit') check_gh_text 'pr edit' bBFtR "$@" ;;
    'pr comment') check_gh_text 'pr comment' bFR "$@" ;;
    'issue create') check_gh_text 'issue create' abFlmptTR "$@" ;;
    'issue edit') check_gh_text 'issue edit' bFtR "$@" ;;
    'issue comment') check_gh_text 'issue comment' bFR "$@" ;;
    'release create' | 'release edit') check_gh_text "$ch_group $ch_action" FntR "$@" ;;
    'pr review') check_gh_text 'pr review' bFR "$@" ;;
    'pr close') check_gh_text 'pr close' cR "$@" ;;
    'issue close') check_gh_text 'issue close' crR "$@" ;;
  esac
}
