#!/bin/sh
# Usage: agents-md.sh plan|apply <root> <templates-dir>
#
# Keeps <root>/AGENTS.md's managed sections in step with the templates, without
# overwriting what the project changed. Prints one JSON line per section:
#   { "section": str, "action": "create|update|keep|conflict", "diff": str?, "detail": str? }
# "plan" writes nothing. "apply" writes AGENTS.md and the ledger in
# <root>/.claude/dev-workflow.json, AGENTS.md first. Exits 0 with conflicts too, and
# 2 on an error. Errors are found before anything is written, except a ledger write
# failing after AGENTS.md; the next run then finds those sections already right and
# records them again. CLAUDE.md is never read: moving its text here comes first.
# AGENTS.md as a symlink, or a .claude folder that leads out of the project through
# one, is an error before anything is read.
#
# A managed section sits between "<!-- dev-workflow:begin <section> -->" and
# "<!-- dev-workflow:end <section> -->", with a blank line inside each, the form
# Prettier keeps, and its ledger key is "AGENTS.md#<section>". Its fingerprint is
# ledger.sh's hash of the text after agents-normalise.awk, so formatting such as line
# endings, blank lines, list markers and table padding doesn't count as an edit, and a
# project that runs Prettier keeps its sections managed. For each section:
#   create    no markers and no record: added after the section before it, else
#             before the one after it, else where an old block was, else at the end
#   update    the text is what was recorded and the template changed: replaced
#   keep      the text is the template's
#   conflict  edited, removed, or with no record: left alone, with the diff
# Sections between markers that the templates don't have are kept and reported.
#
# project.md, the project's own sections, is written only when AGENTS.md is new.
#
# Old blocks, which had no markers, are recognised by legacy.sh: a subsection or
# issues block that matches a published text is removed. One that doesn't is kept,
# with the old heading above it, and reported as "legacy:<block>:<heading>".
#
# New lines follow the file's line ending, CRLF if its first line has one.

SECTIONS="decisions workflow testing tools models communication"

die() {
  printf 'agents-md.sh: %s\n' "$*" >&2
  exit 2
}

for tool in git jq awk diff; do
  command -v "$tool" >/dev/null 2>&1 || die "missing required tool: $tool"
done
[ "$#" -eq 3 ] || die "usage: agents-md.sh plan|apply <root> <templates-dir>"
case $1 in plan | apply) ;; *) die "usage: agents-md.sh plan|apply <root> <templates-dir>" ;; esac
mode=$1
root=$2
tpl=$3
[ -d "$root" ] || die "not a folder: $root"
for s in project $SECTIONS; do
  [ -f "$tpl/$s.md" ] || die "template missing: $tpl/$s.md"
done

here=$(dirname -- "$0")
# shellcheck source=plugins/dev-workflow/scripts/setup/legacy.sh
. "$here/legacy.sh"
# shellcheck source=plugins/dev-workflow/scripts/setup/atomic.sh
. "$here/atomic.sh"
# shellcheck source=plugins/dev-workflow/scripts/setup/agents-legacy.sh
. "$here/agents-legacy.sh"
# shellcheck source=plugins/dev-workflow/scripts/setup/agents-assemble.sh
. "$here/agents-assemble.sh"
# shellcheck source=plugins/dev-workflow/scripts/setup/agents-text.sh
. "$here/agents-text.sh"
# shellcheck source=plugins/dev-workflow/scripts/setup/paths.sh
. "$here/paths.sh"
[ -f "$LEGACY_DIR/issues.md" ] || die "published texts not found in: $LEGACY_DIR"

agents=$root/AGENTS.md
pf=$root/.claude/dev-workflow.json
[ ! -L "$agents" ] || die "AGENTS.md is a symlink; not writing through it: $agents"
[ ! -e "$agents" ] || { [ -f "$agents" ] && [ -r "$agents" ]; } || die "cannot read: $agents"
path_check "$root" .claude/dev-workflow.json || exit 2

work=$(mktemp -d "${TMPDIR:-/tmp}/agents-md.XXXXXX") || die "cannot make a temp folder"
trap 'rm -rf "$work"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir "$work/p"
: >"$work/src"
: >"$work/report"
: >"$work/legacy-report"
: >"$work/ledger"

# --- the file as it is

fresh=true
crlf=false
if [ -e "$agents" ] && [ -n "$(legacy_normalise <"$agents")" ]; then
  fresh=false
  cp "$agents" "$work/src" || die "cannot read: $agents"
  if [ "$(head -n 1 "$work/src" | tail -c 2 | od -An -c | tr -d ' ')" = '\r\n' ]; then crlf=true; fi
  # Lines are handled whole, so a missing final newline is added to the copy.
  [ "$(tail -c 1 "$work/src" | od -An -c | tr -d ' ')" = '\n' ] || newline >>"$work/src"
fi
awk -v out="$work/p" -f "$here/agents-split.awk" "$work/src" || exit 2

# --- where things are

while read -r n kind name; do
  case $kind in
    begin | body | end) printf '%s\n' "$n" >"$work/$kind.$name" ;;
  esac
done <"$work/p/index"
# Sets the drop marks, the anchor and legacy-report.
legacy_pieces "$work" "$work/src" || exit 2

if [ "$fresh" = true ]; then
  report project create >>"$work/report"
else
  report project keep >>"$work/report"
fi

# --- each managed section

previous=
for s in $SECTIONS; do
  key="AGENTS.md#$s"
  new=$(fingerprint "$tpl/$s.md") || exit 2
  recorded=$(sh "$here/ledger.sh" get "$pf" "$key")
  case $? in 0 | 1) ;; *) exit 2 ;; esac
  if [ -f "$work/body.$s" ]; then
    body=$work/p/$(cat "$work/body.$s")
    current=$(fingerprint "$body") || exit 2
    if [ "$current" = "$new" ]; then
      report "$s" keep >>"$work/report"
      [ "$recorded" = "$new" ] || printf '%s %s\n' "$key" "$new" >>"$work/ledger"
    elif [ -n "$recorded" ] && [ "$current" = "$recorded" ]; then
      report "$s" update >>"$work/report"
      printf '%s\n' "$tpl/$s.md" >"$work/replace.$(cat "$work/body.$s")"
      printf '%s %s\n' "$key" "$new" >>"$work/ledger"
    else
      detail=
      [ -n "$recorded" ] || detail="no record of what setup wrote, so it counts as edited"
      report "$s" conflict "$(difference "plugin project" "$tpl/$s.md" "$body")" "$detail" >>"$work/report"
    fi
    previous=$s
    continue
  fi
  if [ -n "$recorded" ]; then
    report "$s" conflict "" "removed by the project, so not added back" >>"$work/report"
    continue
  fi
  report "$s" create >>"$work/report"
  printf '%s %s\n' "$key" "$new" >>"$work/ledger"
  # Where it goes: after the section before it, else before the one after it.
  at=end
  if [ -n "$previous" ]; then
    at=$(($(cat "$work/end.$previous") + 1))
  else
    for later in $SECTIONS; do
      if [ -f "$work/begin.$later" ]; then at=$(cat "$work/begin.$later") && break; fi
    done
    [ "$at" != end ] || [ ! -f "$work/anchor" ] || at=$(cat "$work/anchor")
  fi
  gap=false
  [ ! -s "$work/insert.$at" ] || gap=true
  {
    [ "$gap" = false ] || newline
    printf '<!-- dev-workflow:begin %s -->\n' "$s" | eol
    section "$tpl/$s.md"
    printf '<!-- dev-workflow:end %s -->\n' "$s" | eol
  } >>"$work/insert.$at"
done

# Sections from a newer version of the plugin.
while read -r n kind name; do
  [ "$kind" = begin ] || continue
  case " $SECTIONS " in *" $name "*) continue ;; esac
  report "$name" keep "" "not in this version of the plugin, so left alone" >>"$work/report"
done <"$work/p/index"

cat "$work/report" "$work/legacy-report"

# --- the new file

[ "$mode" = apply ] || exit 0
changed=$fresh
[ -z "$(find "$work" \( -name 'insert.*' -o -name 'replace.*' -o -name 'drop.*' \) -print)" ] || changed=true
if [ "$changed" = true ]; then
  assemble_agents "$work" "$fresh" "$tpl/project.md" >"$work/new" || exit 2
  atomic_write "$agents" <"$work/new" || exit 2
fi
while read -r key hash; do
  sh "$here/ledger.sh" set "$pf" "$key" "$hash" || exit 2
done <"$work/ledger"
