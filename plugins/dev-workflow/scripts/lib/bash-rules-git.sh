#!/bin/sh
# The rules on git commands, for hook-bash.sh, which sets merging on a real merge. Each
# check takes the words after git and ends the script if it denies. Source this file;
# don't run it.
#
# shellcheck disable=SC2034 # hook-bash.sh reads merging.

deny_no_verify() {
  dw_deny "dev-workflow: --no-verify skips the git hooks, and -n means the same on git commit. Run the command without it, and fix what the hooks report."
}

read_commit_flag() {
  case $1 in
    --no-verify | --no-verif | --no-veri | -n) deny_no_verify ;;
  esac
}

read_push_flag() {
  case $1 in
    --no-verify | --no-verif | --no-veri) deny_no_verify ;;
  esac
}

# Sets default_branch, from what origin says, or else main.
find_default_branch() {
  default_branch=$(git -C "$DW_PROJECT_DIR" symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null)
  default_branch=${default_branch#refs/remotes/origin/}
  default_branch=${default_branch:-main}
}

read_git_merge_flag() {
  case $1 in
    --abort | --continue | --quit | --help | -h) gm_merges= ;;
    --ff-only) gm_ff_only=1 ;;
    --ff | --no-ff) gm_ff_only= ;;
    '')
      case $2 in
        "origin/$default_branch" | "remotes/origin/$default_branch" | "refs/remotes/origin/$default_branch") ;;
        '@{u}' | '@{upstream}' | "$default_branch@{u}" | "$default_branch@{upstream}") ;;
        *) gm_elsewhere=1 ;;
      esac
      ;;
  esac
}

check_git_merge() {
  find_default_branch
  gm_merges=1
  gm_ff_only=
  gm_elsewhere=
  walk_flags '--message --file --strategy --strategy-option --into-name' mFsX S read_git_merge_flag "$@"
  [ -n "$gm_merges" ] || return 0
  # Catching up with the remote's own default branch adds nothing that isn't there.
  if [ -n "$gm_ff_only" ] && [ -z "$gm_elsewhere" ]; then
    return 0
  fi
  merging=1
  gm_branch=$(git -C "$DW_PROJECT_DIR" symbolic-ref --quiet --short HEAD 2>/dev/null)
  if [ "$gm_branch" = "$default_branch" ]; then
    dw_deny "dev-workflow: this is a local merge into $default_branch. Merge through a pull request instead."
  fi
}

check_git() {
  gt_subcommand=${1-}
  [ "$#" -eq 0 ] || shift
  case $gt_subcommand in
    commit)
      walk_flags '--message --file --author --date --reuse-message --reedit-message --fixup --squash --template --cleanup --trailer --pathspec-from-file' \
        mFCct uS read_commit_flag "$@"
      ;;
    push) walk_flags '--repo --push-option --receive-pack --exec' o '' read_push_flag "$@" ;;
    merge) check_git_merge "$@" ;;
  esac
}
