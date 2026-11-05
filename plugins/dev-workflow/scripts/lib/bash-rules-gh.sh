#!/bin/sh
# The rules on gh commands, for hook-bash.sh, which sets merging on a real merge and
# command_text to the raw command. Each check takes the words after gh and ends the
# script if it denies. Source this file; don't run it.
#
# shellcheck disable=SC2034,SC2154 # hook-bash.sh sets and reads the variables named above.

# The text as GitHub would show it. People and tools write \n in a body and mean a line.
readable_text() {
  printf '%s\n' "$1" | tr '\037' '\n' | sed 's/\\n/\
/g'
}

deny_attribution() {
  # shellcheck disable=SC2119 # With no file, it reads stdin.
  readable_text "$1" | dw_has_attribution
  case $? in
    0) dw_deny "dev-workflow: AI attribution isn't allowed on GitHub: remove the line that credits the tool, or reword it." ;;
    1) ;;
    *) dw_deny "dev-workflow: could not check this text for AI attribution." ;;
  esac
}

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
      bf_base=$(dw_input '.cwd | strings' 2>/dev/null)
      case $bf_base in
        /*) [ -d "$bf_base" ] || bf_base=$DW_PROJECT_DIR ;;
        *) bf_base=$DW_PROJECT_DIR ;;
      esac
      bf_path=$bf_base/$1
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
    --body | -b | --notes | -n)
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

# check_gh_text <action> <letters taking a value> <words...>: for each gh command that
# writes text for people to read. Flags are per command, as a letter means different
# things in different ones.
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
  walk_flags '--title --body --body-file --notes --notes-file --repo --base --head --assignee --add-assignee --remove-assignee --reviewer --add-reviewer --remove-reviewer --label --add-label --remove-label --project --add-project --remove-project --milestone --template --recover --target --discussion-category --notes-start-tag --type' \
    "$gt_letters" '' read_gh_text_flag "$@"
  [ -z "$gt_help" ] || return 0

  if [ "$gt_action" = 'pr create' ] && [ -n "$gt_fill" ]; then
    dw_deny "dev-workflow: --fill takes the body from the commits, where the closing keyword can't be checked. Pass --title and --body instead."
  fi
  if [ -n "$gt_stdin" ]; then
    [ -n "$gt_inline_stdin" ] || dw_deny "dev-workflow: can't read a body piped in on standard input to check it. Pass --body, a file, or a heredoc."
    # A heredoc is in the raw command and in no word of it.
    gt_body=$gt_body$newline$command_text
  fi

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
  esac
}
