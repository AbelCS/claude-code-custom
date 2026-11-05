#!/bin/sh
# Usage: run.sh --root <dir> --answers <file|-> --plan|--apply
#
# Setup's write step, spec section 7 step 5, for the repo holding <dir>: a subfolder
# means the whole repo, and a worktree is its own. Prints one JSON line per file,
# setting or outside change, in the order they're done:
#   { "path": str, "action": "create|update|keep|conflict", "detail": str }
# A section of AGENTS.md is "AGENTS.md#<section>", and "AGENTS.md#project" is the
# project's own part, written only for a new AGENTS.md. Approved changes outside the
# repo are "plugin:<name>" and "github:<owner/repo>". A conflict is something the
# project edited, or that setup can't do, left alone with why in detail.
#
# --plan writes nothing: what apply would print, worked out on a copy of the files it
# changes, in a temp folder. --apply runs the required tools check first and stops,
# exit 1, before writing anything if one is missing. It then works the plan out the
# same way, so errors are found before anything is written, and writes:
#   1. .claude/dev-workflow.json and .githooks/dev-workflow.env   project-file.sh
#   2. CLAUDE.md as the import, its text moved into AGENTS.md     claude-md.sh
#   3. AGENTS.md's managed sections, and the ledger                agents-md.sh
#   4. the git hooks, turned on                                    install-hooks.sh
#   5. the attribution settings, and approved, the merge rule     settings.sh
#   6. docs/superpowers/specs/ and plans/, each with a .gitkeep, docs/decisions.md
#      and docs/maintenance.md, created only if they aren't there
#   7. approved: the missing plugins, those for screens only with hasScreens
#   8. approved: GitHub's merge settings, for an origin on GitHub  github-settings.sh
# When AGENTS.md is new and CLAUDE.md holds nothing but old rule blocks, AGENTS.md is
# written before CLAUDE.md's text moves into it, so it still gets the project's part.
#
# The answers are JSON: the project file's own fields, and "approvals", whose
# githubSettings, mergePermission and installPlugins are each false unless set.
# skills/setup/references/answers.md has the details.
#
# Nothing is read or written through a folder that leads out of the repo through a
# symlink: that's an error, in --plan too. CLAUDE.md as a symlink to anywhere but
# AGENTS.md is a conflict in the plan, and stops --apply before it writes anything,
# as claude-md.sh won't read through it and the person has to resolve it by hand.
#
# Exits 0 with conflicts too, 1 when required tools are missing, and 2 on any other
# error. $DW_GH and $DW_CLAUDE name gh and claude, for tests.

die() {
  printf 'run.sh: %s\n' "$*" >&2
  exit 2
}

usage="usage: run.sh --root <dir> --answers <file|-> --plan|--apply"
for tool in git jq awk; do
  command -v "$tool" >/dev/null 2>&1 || die "missing required tool: $tool"
done
root=
answers=
mode=
while [ "$#" -gt 0 ]; do
  case $1 in
    --root | --answers)
      [ "$#" -ge 2 ] || die "$usage"
      if [ "$1" = --root ]; then root=$2; else answers=$2; fi
      shift 2
      ;;
    --plan | --apply)
      [ -z "$mode" ] || die "$usage"
      mode=${1#--}
      shift
      ;;
    *) die "$usage" ;;
  esac
done
[ -n "$root" ] && [ -n "$answers" ] && [ -n "$mode" ] || die "$usage"

unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd) || die "cannot find the scripts' folder"
templates=$here/../../skills/setup/templates
CLAUDE=${DW_CLAUDE:-claude}
[ -d "$root" ] || die "not a folder: $root"
root=$(CDPATH='' cd -- "$root" && pwd) || die "cannot open: $root"
if top=$(git -C "$root" rev-parse --show-toplevel 2>/dev/null) && [ -n "$top" ]; then root=$top; fi
# shellcheck source=plugins/dev-workflow/scripts/setup/paths.sh
. "$here/paths.sh"
# Every folder setup reads or writes in, through any script.
path_check "$root" .claude/dev-workflow.json .githooks/pre-push .husky/pre-push \
  docs/decisions.md docs/superpowers/specs docs/superpowers/plans || exit 2

work=$(mktemp -d "${TMPDIR:-/tmp}/setup-run.XXXXXX") || die "cannot make a temp folder"
trap 'rm -rf "$work"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

# --- the answers

if [ "$answers" = - ]; then
  cat >"$work/answers.json" || die "cannot read the answers from stdin"
else
  [ -f "$answers" ] && [ -r "$answers" ] || die "cannot read: $answers"
  cp -- "$answers" "$work/answers.json" || die "cannot read: $answers"
fi
jq -e -s 'length == 1 and (.[0] | type == "object")' "$work/answers.json" >/dev/null 2>&1 ||
  die "the answers aren't valid JSON holding one object"
bad=$(jq -r '(.approvals // {}) as $a
  | if ($a | type) != "object" then "approvals has to be an object"
    else [$a | to_entries[]
      | select((.key | IN("githubSettings", "mergePermission", "installPlugins") | not) or (.value | type) != "boolean")
      | .key] | if length > 0 then "approvals can only be githubSettings, mergePermission and installPlugins, each true or false, not: \(join(", "))" else empty end
    end' "$work/answers.json") || die "cannot read the answers"
[ -z "$bad" ] || die "$bad"
jq 'del(.approvals)' "$work/answers.json" >"$work/facts.json" || die "cannot read the answers"
approved() { [ "$(jq -r --arg k "$1" '.approvals[$k] // false' "$work/answers.json")" = true ]; }

# --- tools, and what's there

tools=$(sh "$here/tools.sh" "$root") || exit 2
if [ "$mode" = apply ]; then
  missing=$(printf '%s\n' "$tools" | jq -r '.required[] | select(.present | not)
    | "  \(.name)\(if .detail then " (\(.detail))" else "" end): \(.install)"') || die "cannot read the tools check"
  if [ -n "$missing" ]; then
    printf 'run.sh: stopped before writing anything, as required tools are missing:\n%s\n' "$missing" >&2
    exit 1
  fi
fi
detected=$(sh "$here/detect.sh" "$root") || exit 2

# --- the steps

# agents <dir> <out>: agents-md.sh apply, its lines as paths.
agents() {
  sh "$here/agents-md.sh" apply "$1" "$templates/agents" >"$work/agents.out" || return 2
  jq -c '{path: "AGENTS.md#\(.section)", action,
    detail: ([.detail, .diff] | map(select(. != null and . != "")) | join("\n"))}' "$work/agents.out" >>"$2"
}

# copy_in <from> <to> <names...>: copies each that's there, a symlink as one pointing
# where the original does: a link to <from>'s AGENTS.md to the copy's, and any other
# to its target in <from>, so the copy still sees each as what it is.
copy_in() {
  _from=$1
  _to=$2
  shift 2
  for _name in "$@"; do
    [ -e "$_from/$_name" ] || [ -L "$_from/$_name" ] || continue
    mkdir -p -- "$(dirname -- "$_to/$_name")" || return 2
    if path_link_is "$_from/$_name" "$_from/AGENTS.md"; then
      ln -s -- "$_to/AGENTS.md" "$_to/$_name" || return 2
    elif [ -L "$_from/$_name" ]; then
      _target=$(readlink -- "$_from/$_name") || return 2
      case $_target in /*) ;; *) _target=$(dirname -- "$_from/$_name")/$_target ;; esac
      ln -s -- "$_target" "$_to/$_name" || return 2
    else
      cp -R -p -- "$_from/$_name" "$_to/$_name" || return 2
    fi
  done
}

# only_old_blocks <dir>: whether AGENTS.md is new and CLAUDE.md's text, moved into it,
# would be nothing but old blocks, which agents-md.sh replaces. Tried on a copy.
only_old_blocks() {
  [ ! -L "$1/AGENTS.md" ] || return 1
  if [ -e "$1/AGENTS.md" ] && grep -q '[^[:space:]]' "$1/AGENTS.md"; then return 1; fi
  rm -rf "$work/probe" && mkdir "$work/probe" || return 1
  copy_in "$1" "$work/probe" CLAUDE.md || return 1
  sh "$here/claude-md.sh" apply "$work/probe" >/dev/null 2>&1 || return 1
  [ -f "$work/probe/AGENTS.md" ] || return 1
  sh "$here/agents-md.sh" apply "$work/probe" "$templates/agents" >/dev/null 2>&1 || return 1
  ! awk '/^<!-- dev-workflow:begin /{ skip = 1 } !skip { print } /^<!-- dev-workflow:end /{ skip = 0 }' \
    "$work/probe/AGENTS.md" | grep -q '[^[:space:]]'
}

# files <dir> <out>: steps 1 to 3, written in <dir>. A CLAUDE.md that claude-md.sh
# refuses is a conflict line, and sets claude_refused.
claude_refused=false
files() {
  sh "$here/project-file.sh" write "$1" "$work/facts.json" >>"$2" || return 2
  if only_old_blocks "$1"; then agents "$1" "$2" || return 2; fi
  sh "$here/claude-md.sh" apply "$1" >>"$2"
  case $? in
    0) ;;
    1) claude_refused=true ;;
    *) return 2 ;;
  esac
  agents "$1" "$2"
}

line() { # <path> <action> [detail]
  jq -cn --arg p "$1" --arg a "$2" --arg d "${3:-}" '{path: $p, action: $a, detail: $d}'
}

# docs <mode> <out>: step 6.
docs() {
  for _d in docs/superpowers/specs docs/superpowers/plans; do
    if [ -d "$root/$_d" ]; then
      line "$_d" keep
    elif [ -e "$root/$_d" ] || [ -L "$root/$_d" ]; then
      line "$_d" conflict "there, but not a folder, so left alone"
    else
      line "$_d" create "with a .gitkeep, so git keeps the empty folder"
      if [ "$1" = apply ]; then
        mkdir -p -- "$root/$_d" && : >"$root/$_d/.gitkeep" || return 2
      fi
    fi
  done >>"$2"
  for _f in decisions maintenance; do
    _path=docs/$_f.md
    if [ -f "$root/$_path" ]; then
      line "$_path" keep
    elif [ -e "$root/$_path" ] || [ -L "$root/$_path" ]; then
      line "$_path" conflict "there, but not a file, so left alone"
    else
      line "$_path" create
      if [ "$1" = apply ]; then
        mkdir -p -- "$root/docs" && cp -- "$templates/docs/$_f.md" "$root/$_path" || return 2
      fi
    fi
  done >>"$2"
}

# plugins <mode> <project-file> <out>: step 7.
plugins() {
  approved installPlugins || return 0
  _screens=$(jq -r '.hasScreens == true' "$2" 2>/dev/null)
  printf '%s\n' "$tools" | jq -r --argjson screens "${_screens:-false}" '.plugins[]
    | select((.present | not) and (.when == "always" or $screens))
    | [.name, (.marketplace // "-"), .id, .install] | join("\t")' >"$work/plugins" || return 2
  while IFS=$(printf '\t') read -r _name _market _id _install; do
    if [ "$1" = plan ]; then
      line "plugin:$_name" create "$_install"
      continue
    fi
    [ "$_market" = - ] || "$CLAUDE" plugin marketplace add "$_market" >/dev/null 2>&1
    if "$CLAUDE" plugin install "$_id" >"$work/install.out" 2>&1; then
      line "plugin:$_name" create "$_install"
    else
      line "plugin:$_name" conflict "couldn't install it: $(cat "$work/install.out"). Run: $_install"
    fi
  done <"$work/plugins" >>"$3"
}

# github <mode> <out>: step 8.
github() {
  approved githubSettings || return 0
  if [ "$(printf '%s\n' "$detected" | jq -r .remote)" != github ]; then
    line github conflict "origin isn't on GitHub, so no GitHub settings were changed" >>"$2"
    return 0
  fi
  _slug=$(git -C "$root" remote get-url origin 2>/dev/null |
    sed -E 's#^.*[Gg][Ii][Tt][Hh][Uu][Bb]\.[Cc][Oo][Mm][:/]+##; s#/+$##; s#\.git$##')
  _plan=
  [ "$1" = apply ] || _plan=--plan
  if ! sh "$here/github-settings.sh" $_plan "$_slug" >>"$2" 2>"$work/github.err"; then
    line "github:$_slug" conflict "$(cat "$work/github.err")" >>"$2"
  fi
}

# Every line for one path becomes one: the strongest action, and every detail.
merge_lines() {
  jq -sc 'def rank: {keep: 0, update: 1, create: 2, conflict: 3}[.];
    reduce .[] as $l ({order: [], by: {}};
      ($l.detail // "") as $d
      | if .by[$l.path] == null then
          .order += [$l.path] | .by[$l.path] = {path: $l.path, action: $l.action, detail: $d}
        else
          .by[$l.path] |= (
            (if ($l.action | rank) > (.action | rank) then .action = $l.action else . end)
            | if $d == "" or $d == .detail then .
              elif .detail == "" then .detail = $d
              else .detail += "\n" + $d end)
        end)
    | .order[] as $p | .by[$p]' "$1"
}

merge=
! approved mergePermission || merge=--allow-merge

# The plan, worked out on a copy for the files that depend on each other.
mkdir "$work/stage" "$work/plan" || die "cannot write in: $work"
: >"$work/plan/lines"
copy_in "$root" "$work/stage" AGENTS.md CLAUDE.md .claude/dev-workflow.json .githooks/dev-workflow.env ||
  die "cannot copy the files setup changes into: $work/stage"
files "$work/stage" "$work/plan/lines" || exit 2
sh "$here/install-hooks.sh" plan "$root" "$templates/githooks" >>"$work/plan/lines" || exit 2
# shellcheck disable=SC2086 # One flag or none.
sh "$here/settings.sh" plan "$root" $merge >>"$work/plan/lines" || exit 2
docs plan "$work/plan/lines" || exit 2
plugins plan "$work/stage/.claude/dev-workflow.json" "$work/plan/lines" || exit 2
github plan "$work/plan/lines" || exit 2

if [ "$mode" = plan ]; then
  merge_lines "$work/plan/lines"
  exit 0
fi
[ "$claude_refused" = false ] ||
  die "stopped before writing anything: CLAUDE.md is a link to somewhere other than AGENTS.md. Resolve it by hand, then run setup again."

: >"$work/lines"
files "$root" "$work/lines" || exit 2
sh "$here/install-hooks.sh" apply "$root" "$templates/githooks" >>"$work/lines" || exit 2
# shellcheck disable=SC2086 # One flag or none.
sh "$here/settings.sh" apply "$root" $merge >>"$work/lines" || exit 2
docs apply "$work/lines" || exit 2
plugins apply "$root/.claude/dev-workflow.json" "$work/lines" || exit 2
github apply "$work/lines" || exit 2
merge_lines "$work/lines"
