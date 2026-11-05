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
# githubSettings, mergePermission, installPlugins and moveGitHooks are each false
# unless set. moveGitHooks moves the hooks in .git/hooks into .githooks before the
# hooks are turned on, which would stop them: install-hooks.sh --move-git-hooks.
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
      | select((.key | IN("githubSettings", "mergePermission", "installPlugins", "moveGitHooks") | not) or (.value | type) != "boolean")
      | .key] | if length > 0 then "approvals can only be githubSettings, mergePermission, installPlugins and moveGitHooks, each true or false, not: \(join(", "))" else empty end
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

# shellcheck source=plugins/dev-workflow/scripts/setup/run-steps.sh
. "$here/run-steps.sh"

merge=
! approved mergePermission || merge=--allow-merge
move=
! approved moveGitHooks || move=--move-git-hooks

# The plan, worked out on a copy for the files that depend on each other.
mkdir "$work/stage" "$work/plan" || die "cannot write in: $work"
: >"$work/plan/lines"
copy_in "$root" "$work/stage" AGENTS.md CLAUDE.md .claude/dev-workflow.json .githooks/dev-workflow.env ||
  die "cannot copy the files setup changes into: $work/stage"
files "$work/stage" "$work/plan/lines" || exit 2
# shellcheck disable=SC2086 # One flag or none.
sh "$here/install-hooks.sh" plan "$root" "$templates/githooks" $move >>"$work/plan/lines" || exit 2
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
# shellcheck disable=SC2086 # One flag or none.
sh "$here/install-hooks.sh" apply "$root" "$templates/githooks" $move >>"$work/lines" || exit 2
# shellcheck disable=SC2086 # One flag or none.
sh "$here/settings.sh" apply "$root" $merge >>"$work/lines" || exit 2
docs apply "$work/lines" || exit 2
plugins apply "$root/.claude/dev-workflow.json" "$work/lines" || exit 2
github apply "$work/lines" || exit 2
merge_lines "$work/lines"
