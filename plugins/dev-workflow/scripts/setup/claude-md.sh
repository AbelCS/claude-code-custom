#!/bin/sh
# Usage: claude-md.sh plan|apply <root>
#
# Makes <root>/CLAUDE.md exactly "@AGENTS.md" and a newline, the import that has
# Claude Code read AGENTS.md. Prints one JSON line per file:
#   { "path": str, "action": "create|update|keep|conflict", "detail": str? }
# "plan" writes nothing. Exits 1 on a conflict and 2 on an error, both before
# anything is written.
#
# What CLAUDE.md holds, as legacy_claude_state tells it:
#   absent   the import is created
#   import   kept, or rewritten to the exact bytes if only line endings or spaces differ
#   pointer  an old pointer published here: replaced with the import
#   content  its text moves to the end of AGENTS.md first, after a blank line, making
#            AGENTS.md if there's none. Then CLAUDE.md becomes the import.
#   symlink  never read through, as a hostile repo could link it to a private file
#            outside it. A link straight to this AGENTS.md is replaced by a regular
#            file holding the import, moving nothing. Any other, in the repo or out,
#            dangling or a chain of links, is a conflict, printed as one line for
#            CLAUDE.md with exit 1, and left for the person to resolve by hand.
# Lines that are just @AGENTS.md don't move, nor do blank lines at either end. Text
# AGENTS.md already ends with isn't added again, so a rerun after a failure between
# the two writes doesn't repeat it.
# Old rule blocks that move are left for agents-md.sh, which must run after this.

die() {
  printf 'claude-md.sh: %s\n' "$*" >&2
  exit 2
}

for tool in jq awk; do
  command -v "$tool" >/dev/null 2>&1 || die "missing required tool: $tool"
done
usage="usage: claude-md.sh plan|apply <root>"
[ "$#" -eq 2 ] || die "$usage"
case $1 in plan | apply) ;; *) die "$usage" ;; esac
mode=$1
[ -d "$2" ] || die "not a folder: $2"

here=$(dirname -- "$0")
# shellcheck source=plugins/dev-workflow/scripts/setup/legacy.sh
. "$here/legacy.sh"
# shellcheck source=plugins/dev-workflow/scripts/setup/atomic.sh
. "$here/atomic.sh"
# shellcheck source=plugins/dev-workflow/scripts/setup/paths.sh
. "$here/paths.sh"
[ -f "$LEGACY_DIR/issues.md" ] || die "published texts not found in: $LEGACY_DIR"

claude=$2/CLAUDE.md
agents=$2/AGENTS.md
[ ! -L "$agents" ] || die "AGENTS.md is a symlink; not writing through it: $agents"
[ ! -e "$agents" ] || { [ -f "$agents" ] && [ -r "$agents" ]; } || die "cannot read: $agents"

work=$(mktemp -d "${TMPDIR:-/tmp}/claude-md.XXXXXX") || die "cannot make a temp folder"
trap 'rm -rf "$work"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
printf '@AGENTS.md\n' >"$work/import"

report() { # <path> <action> [detail]
  jq -cn --arg p "$1" --arg a "$2" --arg d "${3:-}" \
    '{path: $p, action: $a} + (if $d == "" then {} else {detail: $d} end)'
}

state=$(legacy_claude_state "$claude")
detail=
: >"$work/moved"
case $state in
  absent)
    report CLAUDE.md create
    [ "$mode" = apply ] || exit 0
    atomic_write "$claude" <"$work/import" || exit 2
    exit 0
    ;;
  import)
    if cmp -s "$claude" "$work/import"; then
      report CLAUDE.md keep
      exit 0
    fi
    detail="the import, rewritten to its exact form"
    ;;
  pointer) detail="an old pointer to AGENTS.md, replaced with the import" ;;
  symlink)
    if ! path_link_is "$claude" "$agents"; then
      report CLAUDE.md conflict "a link to somewhere other than AGENTS.md, so setup won't read it or move its text: resolve it by hand, then run setup again"
      printf 'claude-md.sh: CLAUDE.md is a link to somewhere other than AGENTS.md, so it is not read and nothing is written. Resolve it by hand, then run setup again: %s\n' "$claude" >&2
      exit 1
    fi
    detail="a symlink to AGENTS.md, replaced by a regular file holding the import"
    ;;
  content)
    if [ -e "$claude" ]; then
      # The lines that move: not the import, and no blank lines at either end.
      awk '
        { line = $0; sub(/[ \t\r\f\v]+$/, "", line) }
        line == "@AGENTS.md" { next }
        { lines[++n] = $0 }
        line != "" { if (!first) first = n; last = n }
        END { if (first) for (i = first; i <= last; i++) print lines[i] }
      ' "$claude" >"$work/moved" || die "cannot read: $claude"
    fi
    ;;
  *) die "cannot tell what CLAUDE.md is: $claude" ;;
esac

# Whether the text is already at the end of AGENTS.md.
if [ -s "$work/moved" ] && [ -e "$agents" ]; then
  legacy_normalise <"$work/moved" >"$work/moved-norm"
  count=$(wc -l <"$work/moved-norm")
  legacy_normalise <"$agents" | tail -n "$count" >"$work/agents-tail"
  if cmp -s "$work/moved-norm" "$work/agents-tail"; then : >"$work/moved"; fi
fi

if [ -s "$work/moved" ]; then
  if [ -e "$agents" ] && [ -n "$(legacy_normalise <"$agents")" ]; then
    nl='\n'
    if [ "$(head -n 1 "$agents" | tail -c 2 | od -An -c | tr -d ' ')" = '\r\n' ]; then nl='\r\n'; fi
    {
      cat "$agents"
      # shellcheck disable=SC2059 # The format is the line ending.
      [ "$(tail -c 1 "$agents" | od -An -c | tr -d ' ')" = '\n' ] || printf "$nl"
      # shellcheck disable=SC2059
      printf "$nl"
      cat "$work/moved"
    } >"$work/agents" || die "cannot read: $agents"
    report AGENTS.md update "gets the text moved from CLAUDE.md, at the end"
  else
    cp "$work/moved" "$work/agents" || die "cannot write in: $work"
    if [ -e "$agents" ]; then
      report AGENTS.md update "gets the text moved from CLAUDE.md"
    else
      report AGENTS.md create "holds the text moved from CLAUDE.md"
    fi
  fi
  detail="its text moved to AGENTS.md, and replaced with the import"
fi
report CLAUDE.md update "$detail"

[ "$mode" = apply ] || exit 0
if [ -f "$work/agents" ]; then
  atomic_write "$agents" <"$work/agents" || exit 2
fi
# atomic_write won't replace a symlink, so the link goes first.
if [ -L "$claude" ]; then
  rm -f -- "$claude" || die "cannot remove the symlink: $claude"
fi
atomic_write "$claude" <"$work/import" || exit 2
