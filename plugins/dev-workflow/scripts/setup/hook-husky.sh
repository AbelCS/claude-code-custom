#!/bin/sh
# activate_husky <root> <work>: has each husky hook run the dev-workflow hook of its
# name, first. Source this file, from install-hooks.sh, which has report, step, $HOOKS
# and $here; don't run it. Returns 2 on an error.
#
# The call is a block between "# dev-workflow:begin" and "# dev-workflow:end" lines,
# at the start of .husky/<hook>, after a shebang and husky's own husky.sh line if the
# file has them. What's there stays as it is, after it. In pre-push the block saves
# git's input first, so the dev-workflow hook reads it and the rest of the hook still
# does too. The block's hash is in the ledger as ".husky/<hook>#dev-workflow":
#   create    no file: one holding the block, executable
#   update    no block yet: added. Or the block is what setup recorded, and this
#             version's differs: replaced
#   keep      the block is this version's
#   conflict  the block was edited, has no record, or its markers are broken, or the
#             file is a symlink: left alone, with what to add

# shellcheck disable=SC2154 # install-hooks.sh sets here.

_husky_block() { # <hook>: the block
  echo '# dev-workflow:begin'
  if [ "$1" = pre-push ]; then
    cat <<'EOF'
# Git's input is saved, so the dev-workflow hook reads it and so does the rest here.
dw_input=$(mktemp) || exit 1
cat >"$dw_input" || { rm -f "$dw_input"; exit 1; }
exec 3<"$dw_input" <"$dw_input"
rm -f "$dw_input"
.githooks/pre-push "$@" <&3 || exit $?
exec 3<&-
EOF
  else
    printf '.githooks/%s "$@" || exit $?\n' "$1"
  fi
  echo '# dev-workflow:end'
}

# _husky_split <file> <dir>: the file in three parts, <dir>/head, the shebang and
# husky.sh lines that stay first, <dir>/block, any dev-workflow block, and <dir>/rest,
# everything else. Exits 1 if the markers aren't one begin then one end.
_husky_split() {
  awk -v dir="$2" '
    { line = $0; sub(/[ \t\r]+$/, "", line) }
    NR == 1 && line ~ /^#!/ { print > (dir "/head"); next }
    NR <= 2 && line ~ /^\. .*husky\.sh"?$/ { print > (dir "/head"); next }
    line == "# dev-workflow:begin" {
      if (seen) bad = 1
      seen = inside = 1
      print > (dir "/block")
      next
    }
    line == "# dev-workflow:end" {
      if (!inside) bad = 1
      inside = 0
      print > (dir "/block")
      next
    }
    inside { print > (dir "/block"); next }
    { print > (dir "/rest") }
    END { exit (bad || inside) ? 1 : 0 }
  ' "$1"
}

activate_husky() {
  for _hook in $HOOKS; do
    _file=$1/.husky/$_hook
    _key=.husky/$_hook#dev-workflow
    _part=$2/husky.$_hook
    mkdir -p "$_part" || return 2
    _husky_block "$_hook" >"$_part/ours" || return 2
    _new=$(sh "$here/ledger.sh" hash "$_part/ours") || return 2
    _recorded=$(sh "$here/ledger.sh" get "$1/.claude/dev-workflow.json" "$_key")
    case $? in 0 | 1) ;; *) return 2 ;; esac
    _add="add this block at its start:
$(cat "$_part/ours")"
    if [ -L "$_file" ]; then
      report ".husky/$_hook" conflict "a symlink, so left alone: $_add"
      continue
    fi
    if [ ! -e "$_file" ]; then
      report ".husky/$_hook" create "runs the dev-workflow hook"
      step write "$_file" "$_part/ours" 1
      step ledger "$_key" "$_new"
      continue
    fi
    [ -f "$_file" ] && [ -r "$_file" ] || {
      printf 'cannot read: %s\n' "$_file" >&2
      return 2
    }
    if ! _husky_split "$_file" "$_part"; then
      report ".husky/$_hook" conflict "its dev-workflow markers aren't one begin line then one end line, so it's left alone: fix them, or remove them and what's between, then run setup again"
      continue
    fi
    _detail="runs the dev-workflow hook first, before what's there"
    if [ -f "$_part/block" ]; then
      _current=$(sh "$here/ledger.sh" hash "$_part/block") || return 2
      if [ "$_current" = "$_new" ]; then
        [ "$_recorded" = "$_new" ] || step ledger "$_key" "$_new"
        report ".husky/$_hook" keep
        continue
      fi
      if [ "$_recorded" != "$_current" ]; then
        _why="the dev-workflow block was edited"
        [ -n "$_recorded" ] || _why="there's no record of what setup wrote in the dev-workflow block, so it counts as edited"
        report ".husky/$_hook" conflict "$_why, so it's left alone:
$(printf -- '--- plugin\n+++ project\n' && diff -u "$_part/ours" "$_part/block" | sed '1,2d')"
        continue
      fi
      _detail="the dev-workflow block is brought up to date"
    fi
    {
      [ ! -f "$_part/head" ] || cat "$_part/head"
      cat "$_part/ours"
      [ ! -f "$_part/rest" ] || cat "$_part/rest"
    } >"$_part/new" || return 2
    # A last line with no newline stays whole.
    [ "$(tail -c 1 "$_part/new" | od -An -c | tr -d ' ')" = '\n' ] || echo >>"$_part/new"
    report ".husky/$_hook" update "$_detail"
    step write "$_file" "$_part/new" 0
    step ledger "$_key" "$_new"
  done
}
