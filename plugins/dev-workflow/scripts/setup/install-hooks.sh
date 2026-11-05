#!/bin/sh
# Usage: install-hooks.sh plan|apply <root> <templates-dir>
#
# Copies the git hooks in <templates-dir> (skills/setup/templates/githooks) into
# <root>/.githooks/, and turns them on. Prints one JSON line per file or setting:
#   { "path": str, "action": "create|update|keep|conflict", "detail": str? }
# "plan" writes nothing. "apply" writes the hooks, then turns them on. Exits 0 with
# conflicts too, and 2 on an error, found before anything is written.
#
# Each copied file is in the ledger in <root>/.claude/dev-workflow.json, keyed by its
# path, such as ".githooks/pre-push", with ledger.sh's hash of the exact bytes:
#   create    not there: copied
#   update    what setup recorded, and the template changed: replaced
#   keep      the template's already
#   conflict  edited, or with no record: left alone, with the diff
# Each hook ends executable, whatever mode the template had, since git skips one
# that isn't. A hook that only lost that mode is "update". dev-workflow.env, which
# the hooks read, is project-file.sh's.
#
# How the hooks are turned on is in hook-activate.sh. A folder it writes in that
# leads out of the project through a symlink, .githooks, .claude or .husky, is an
# error before anything is read or written.

HOOKS="commit-msg pre-commit pre-push"
FILES="dw-lib.sh $HOOKS"

die() {
  printf 'install-hooks.sh: %s\n' "$*" >&2
  exit 2
}

for tool in git jq awk diff; do
  command -v "$tool" >/dev/null 2>&1 || die "missing required tool: $tool"
done
usage="usage: install-hooks.sh plan|apply <root> <templates-dir>"
[ "$#" -eq 3 ] || die "$usage"
case $1 in plan | apply) ;; *) die "$usage" ;; esac
mode=$1
root=$2
tpl=$3
[ -d "$root" ] || die "not a folder: $root"
for f in $FILES; do
  [ -f "$tpl/$f" ] || die "template missing: $tpl/$f"
done
[ ! -e "$root/.githooks" ] || [ -d "$root/.githooks" ] || die "not a folder: $root/.githooks"

here=$(dirname -- "$0")
# shellcheck source=plugins/dev-workflow/scripts/setup/atomic.sh
. "$here/atomic.sh"
# shellcheck source=plugins/dev-workflow/scripts/setup/json.sh
. "$here/json.sh"
# shellcheck source=plugins/dev-workflow/scripts/setup/hook-activate.sh
. "$here/hook-activate.sh"
# shellcheck source=plugins/dev-workflow/scripts/setup/paths.sh
. "$here/paths.sh"
path_check "$root" .githooks/pre-push .claude/dev-workflow.json .husky/pre-push || exit 2

pf=$root/.claude/dev-workflow.json
work=$(mktemp -d "${TMPDIR:-/tmp}/install-hooks.XXXXXX") || die "cannot make a temp folder"
trap 'rm -rf "$work"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
# What apply does, one step a line, its words split by tabs, as paths can hold
# spaces: "write <target> <source> <0|1 executable>", "chmod <target>",
# "ledger <key> <hash>" or "hooks-path".
: >"$work/steps"
tab=$(printf '\t')
step() { # <words...>: adds a step
  _step=$1
  shift
  for _word in "$@"; do _step="$_step$tab$_word"; done
  printf '%s\n' "$_step" >>"$work/steps"
}

report() { # <path> <action> [detail]
  jq -cn --arg p "$1" --arg a "$2" --arg d "${3:-}" \
    '{path: $p, action: $a} + (if $d == "" then {} else {detail: $d} end)'
}

is_hook() { case " $HOOKS " in *" $1 "*) return 0 ;; esac; return 1; }

# --- the files

for f in $FILES; do
  key=.githooks/$f
  target=$root/$key
  exec=0
  ! is_hook "$f" || exec=1
  new=$(sh "$here/ledger.sh" hash "$tpl/$f") || exit 2
  recorded=$(sh "$here/ledger.sh" get "$pf" "$key")
  case $? in 0 | 1) ;; *) exit 2 ;; esac

  if [ -L "$target" ]; then
    report "$key" conflict "a symlink, so left alone"
    continue
  fi
  if [ ! -e "$target" ]; then
    report "$key" create
    step write "$target" "$tpl/$f" "$exec"
    step ledger "$key" "$new"
    continue
  fi
  [ -f "$target" ] && [ -r "$target" ] || die "cannot read: $target"
  current=$(sh "$here/ledger.sh" hash "$target") || exit 2
  if [ "$current" = "$new" ]; then
    [ "$recorded" = "$new" ] || step ledger "$key" "$new"
    if [ "$exec" = 1 ] && [ ! -x "$target" ]; then
      report "$key" update "made executable again, as git skips a hook that isn't"
      step chmod "$target"
    else
      report "$key" keep
    fi
  elif [ -n "$recorded" ] && [ "$current" = "$recorded" ]; then
    report "$key" update
    step write "$target" "$tpl/$f" "$exec"
    step ledger "$key" "$new"
  else
    detail=$(printf -- '--- plugin\n+++ project\n' && diff -u "$tpl/$f" "$target" | sed '1,2d')
    [ -n "$recorded" ] || detail="no record of what setup wrote, so it counts as edited
$detail"
    if [ "$exec" = 1 ] && [ ! -x "$target" ]; then
      detail="it isn't executable, so git skips it
$detail"
    fi
    report "$key" conflict "$detail"
  fi
done

# --- turning them on

activate_plan "$root" "$work" || exit 2

[ "$mode" = apply ] || exit 0
mkdir -p -- "$root/.githooks" || die "cannot create: $root/.githooks"
while IFS=$tab read -r kind a b c; do
  case $kind in
    write)
      atomic_write "$a" <"$b" || exit 2
      [ "$c" = 0 ] || chmod +x "$a" || die "cannot make executable: $a"
      ;;
    chmod) chmod +x "$a" || die "cannot make executable: $a" ;;
    ledger) sh "$here/ledger.sh" set "$pf" "$a" "$b" || exit 2 ;;
    hooks-path) git -C "$root" config --local core.hooksPath .githooks || die "cannot set core.hooksPath in: $root" ;;
  esac
done <"$work/steps"
