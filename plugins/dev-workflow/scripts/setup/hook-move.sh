#!/bin/sh
# move_git_hooks <root> <names>: before core.hooksPath is set to .githooks, which stops
# git running the hooks in .git/hooks, decides what happens to the executable ones
# detect.sh lists. Source this file, from install-hooks.sh, which has report, step,
# is_hook and $MOVE_GIT_HOOKS; don't run it. Returns 0 to go on turning the hooks on,
# 1 when they stay off, with a conflict reported, and 2 on an error.
#
# Without the person's yes, $MOVE_GIT_HOOKS empty, it's a conflict naming them, and the
# hooks aren't turned on: no core.hooksPath and no prepare script. With it, each moves
# into .githooks: one with a dev-workflow hook of its name as <name>.local, which that
# hook runs first, and any other under its own name, where git finds it once the hooks
# are on. None moves if any can't: a symlink, whose link may not work from there, or
# one whose place in .githooks is taken.

# shellcheck disable=SC2154 # install-hooks.sh sets here.
# shellcheck source=plugins/dev-workflow/scripts/setup/detect-git.sh
. "$here/detect-git.sh"

_move_dest() { # <name>: where it goes in .githooks
  if is_hook "$1"; then printf '%s.local\n' "$1"; else printf '%s\n' "$1"; fi
}

move_git_hooks() {
  _dir=$(git_hooks_dir "$1") || {
    printf 'cannot find the hooks folder of: %s\n' "$1" >&2
    return 2
  }
  _shown=${_dir#"$1"/}
  # shellcheck disable=SC2086 # Plain names, split on purpose.
  _list=$(printf '%s\n' $2 | LC_ALL=C sort | tr '\n' ',' | sed 's/,$//; s/,/, /g')
  if [ -z "${MOVE_GIT_HOOKS:-}" ]; then
    report "$_shown" conflict "git runs these hooks from $_shown: $_list. Turning on the dev-workflow hooks in .githooks would stop them, so they're left off: core.hooksPath stays unset, and no prepare script is added. Setup can move them into .githooks, with the person's yes: one with a dev-workflow hook of the same name as <name>.local, such as .githooks/pre-commit.local, which that hook runs first, and any other under its own name. Or move or remove them by hand, then run setup again."
    return 1
  fi
  _blocked=
  for _name in $2; do
    _dest=$(_move_dest "$_name")
    if [ -L "$_dir/$_name" ]; then
      _blocked="$_blocked
  $_shown/$_name is a symlink, which may not work from .githooks: move it by hand"
    elif [ -e "$1/.githooks/$_dest" ] || [ -L "$1/.githooks/$_dest" ]; then
      _blocked="$_blocked
  .githooks/$_dest is already there"
    fi
  done
  if [ -n "$_blocked" ]; then
    report "$_shown" conflict "git runs these hooks from $_shown: $_list. They can't all move into .githooks, so none does, and the dev-workflow hooks are left off, with core.hooksPath unset:$_blocked"
    return 1
  fi
  for _name in $2; do
    _dest=$(_move_dest "$_name")
    if is_hook "$_name"; then
      report "$_shown/$_name" update "moved to .githooks/$_dest, which .githooks/$_name runs first"
    else
      report "$_shown/$_name" update "moved to .githooks/$_dest, where git runs it once core.hooksPath is .githooks"
    fi
    step move "$_dir/$_name" "$1/.githooks/$_dest"
  done
}
