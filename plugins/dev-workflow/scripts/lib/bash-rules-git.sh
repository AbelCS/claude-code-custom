#!/bin/sh
# The rules on git commands, for hook-bash.sh, which reads merging on a real merge and
# starts branch_moves, move_unknown, walk_folder and walk_unknown empty for a command.
# Each check takes the words after git, or cd, and ends the script if it denies. Source
# this file; don't run it.
#
# shellcheck disable=SC2034,SC2154 # hook-bash.sh sets and reads these variables.

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

# --- Following folders within a command. The splitter flattens subshells, so a cd in one
# counts for the rest of the command, as if it weren't in one.

is_folder() {
  [ -d "$1" ] && [ -x "$1" ]
}

# Sets walk_folder to where the command has got to, starting from the session's folder.
# walk_unknown is set once that can't be told from the command's text.
find_walk_folder() {
  if [ -z "$walk_folder" ]; then
    dw_session_folder
    walk_folder=$DW_SESSION_FOLDER
  fi
}

check_cd() {
  find_walk_folder
  while [ "$#" -gt 0 ]; do
    case $1 in
      --)
        shift
        break
        ;;
      '' | - | [!-]*) break ;;
      *) shift ;;
    esac
  done
  if [ "$#" -eq 0 ]; then
    cd_path=${HOME:-}
  else
    case $1 in
      \~) cd_path=${HOME:-} ;;
      \~/*) cd_path=${HOME:+$HOME/${1#\~/}} ;;
      # The last folder, and someone else's home, leave nothing to go on.
      - | \~*) cd_path= ;;
      /*) cd_path=$1 ;;
      *)
        # From a folder that can't be told, a relative path says no more.
        [ -z "$walk_unknown" ] || return 0
        cd_path=$walk_folder/$1
        ;;
    esac
  fi
  if is_folder "$cd_path"; then
    walk_folder=$cd_path
    walk_unknown=
  else
    walk_unknown=1
  fi
}

# Sets git_path to the folder a git command acts in, and git_root to its working tree,
# whose branch that is. It's where the command has got to, or the folder -C names from
# there. git_c holds the path from -C, if any. git_unknown is set if it can't be told.
find_git_folder() {
  find_walk_folder
  git_unknown=$walk_unknown
  case $git_c in
    '') git_path=$walk_folder ;;
    /*)
      git_path=$git_c
      git_unknown=
      ;;
    \~/*)
      git_path=${HOME:+$HOME/${git_c#\~/}}
      git_unknown=
      ;;
    *) git_path=$walk_folder/$git_c ;;
  esac
  if ! is_folder "$git_path"; then
    git_path=$walk_folder
    git_unknown=1
  fi
  git_root=$(git -C "$git_path" rev-parse --show-toplevel 2>/dev/null)
  git_root=${git_root:-$git_path}
}

# Sets default_branch, from what origin says, or else main.
find_default_branch() {
  default_branch=$(git -C "$git_path" symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null)
  default_branch=${default_branch#refs/remotes/origin/}
  default_branch=${default_branch:-main}
}

# --- Following moves within a command. No branch name can hold a ?, so that means one
# that can't be told.
#
# Known limit: a move that fails still counts. Text can't show whether git switch will
# work, so git switch main || git merge x is judged as if on main. A subshell doesn't
# change this, as HEAD lives in the repo and a subshell can't confine a branch switch.

unknown_branch='?'

# moved_to <branch>: git_root is on it from now on. Empty means no branch. A move in a
# folder that can't be told could be in any working tree, which move_unknown records.
moved_to() {
  if [ -n "$git_unknown" ]; then
    move_unknown=1
  else
    branch_moves=$branch_moves$git_root$word_end$1$newline
  fi
}

# Whether a word as written says what it names, and isn't relative or an expansion.
is_plain_name() {
  case $1 in
    '' | - | @ | HEAD | *[\$\`]* | @\{*) return 1 ;;
  esac
}

# moved_to_named <name>: moved_to for a name as written, if it's one that says.
moved_to_named() {
  if is_plain_name "$1"; then
    moved_to "$1"
  else
    moved_to "$unknown_branch"
  fi
}

# Sets branch_now to what git_root is on at this point in the command.
find_branch_now() {
  bn_rest=$branch_moves
  bn_moved=
  while [ -n "$bn_rest" ]; do
    bn_move=${bn_rest%%"$newline"*}
    bn_rest=${bn_rest#*"$newline"}
    case $bn_move in
      "$git_root$word_end"*)
        bn_moved=1
        branch_now=${bn_move#*"$word_end"}
        ;;
    esac
  done
  [ -n "$bn_moved" ] || branch_now=$(git -C "$git_path" symbolic-ref --quiet --short HEAD 2>/dev/null)
}

read_switch_flag() {
  case $1 in
    -c | -C | --create | --force-create | --orphan)
      mv_new=${2-}
      mv_has_new=1
      ;;
    -d | --detach) mv_detach=1 ;;
    -t | --track) mv_track=1 ;;
    --help | -h) mv_help=1 ;;
    '')
      mv_count=$((mv_count + 1))
      [ "$mv_count" -gt 1 ] || mv_target=$2
      ;;
  esac
}

reset_move() {
  mv_new=
  mv_has_new=
  mv_detach=
  mv_track=
  mv_help=
  mv_paths=
  mv_count=0
  mv_target=
}

check_git_switch() {
  find_git_folder
  reset_move
  walk_flags '--create --force-create --orphan --conflict' cC '' read_switch_flag "$@"
  if [ -n "$mv_help" ]; then
    return 0
  elif [ -n "$mv_has_new" ]; then
    moved_to_named "$mv_new"
  elif [ -n "$mv_detach" ]; then
    moved_to ''
  elif [ -n "$mv_track" ]; then
    moved_to "$unknown_branch"
  elif [ "$mv_count" -gt 0 ]; then
    moved_to_named "$mv_target"
  fi
}

read_checkout_flag() {
  case $1 in
    -b | -B | --orphan)
      mv_new=${2-}
      mv_has_new=1
      ;;
    -d | --detach) mv_detach=1 ;;
    -t | --track) mv_track=1 ;;
    -p | --patch | --ours | --theirs | -2 | -3 | --pathspec-from-file) mv_paths=1 ;;
    --help | -h) mv_help=1 ;;
    '')
      mv_count=$((mv_count + 1))
      [ "$mv_count" -gt 1 ] || mv_target=$2
      ;;
  esac
}

# Takes the one word of git checkout <word>, which can name a branch, a path or a commit.
moved_by_checkout_word() {
  if ! is_plain_name "$1" || [ -n "$git_unknown" ]; then
    moved_to "$unknown_branch"
    return 0
  fi
  find_default_branch
  if [ "$1" = "$default_branch" ] ||
    git -C "$git_path" show-ref --verify --quiet "refs/heads/$1" 2>/dev/null; then
    moved_to "$1"
  # A -- after it says it isn't a path, whatever is on disk.
  elif [ -n "$ck_ends_with_dashes" ] || [ ! -e "$git_path/$1" ]; then
    moved_to "$unknown_branch"
  fi
}

check_git_checkout() {
  find_git_folder
  reset_move
  # Words after a -- are paths. With nothing after it, the word before is a branch.
  ck_ends_with_dashes=
  for ck_word in "$@"; do
    if [ -n "$ck_ends_with_dashes" ]; then
      mv_paths=1
      ck_ends_with_dashes=
      break
    fi
    [ "$ck_word" != -- ] || ck_ends_with_dashes=1
  done
  walk_flags '--orphan --conflict --pathspec-from-file --unified --inter-hunk-context' bB U read_checkout_flag "$@"
  if [ -n "$mv_help" ]; then
    return 0
  elif [ -n "$mv_has_new" ]; then
    moved_to_named "$mv_new"
  elif [ -n "$mv_detach" ]; then
    moved_to ''
  elif [ -n "$mv_paths" ]; then
    return 0
  elif [ -n "$mv_track" ]; then
    moved_to "$unknown_branch"
  elif [ "$mv_count" -eq 1 ]; then
    moved_by_checkout_word "$mv_target"
  fi
}

# --- Merges

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
  find_git_folder
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
  find_branch_now
  if [ -n "$git_unknown" ] || [ -n "$move_unknown" ] || [ "$branch_now" = "$unknown_branch" ]; then
    dw_deny "dev-workflow: this merges after moving to a branch or folder that can't be told from the command's text, which could be a local merge into $default_branch. Run them separately."
  fi
  case $branch_now in
    "$default_branch")
      dw_deny "dev-workflow: this is a local merge into $default_branch. Merge through a pull request instead."
      ;;
  esac
}

check_git() {
  git_c=
  while [ "$#" -ge 2 ] && [ "$1" = -C ]; do
    case $2 in
      /* | \~/*) git_c=$2 ;;
      *) git_c=${git_c:+$git_c/}$2 ;;
    esac
    shift 2
  done
  gt_subcommand=${1-}
  [ "$#" -eq 0 ] || shift
  case $gt_subcommand in
    commit)
      walk_flags '--message --file --author --date --reuse-message --reedit-message --fixup --squash --template --cleanup --trailer --pathspec-from-file' \
        mFCct uS read_commit_flag "$@"
      ;;
    push) walk_flags '--repo --push-option --receive-pack --exec' o '' read_push_flag "$@" ;;
    merge) check_git_merge "$@" ;;
    switch) check_git_switch "$@" ;;
    checkout) check_git_checkout "$@" ;;
  esac
}
