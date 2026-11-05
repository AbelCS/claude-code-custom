#!/bin/sh
# Usage: settings.sh plan|apply <root> [--allow-merge]
#
# Merges into <root>/.claude/settings.json the setting that stops Claude Code adding
# its attribution to commits and pull requests:
#   { "attribution": { "commit": "", "pr": "", "sessionUrl": false } }
# This form, not "attribution": false, because older versions reject a whole file
# holding that. Other keys, and other keys in attribution, are kept.
#
# With --allow-merge, which the person has to approve, it also adds the permission
# rule "Bash(gh pr merge *)" to permissions.allow in .claude/settings.local.json, so
# auto mode doesn't block the agent merging its own pull requests.
#
# Prints one JSON line per file: { "path": str, "action": "create|update|keep",
# "detail": str? }. "plan" writes nothing. A file already holding the settings is
# left byte for byte. Exits 2, before writing anything, on bad usage, a file that
# isn't one JSON object, or a .claude folder that leads out of the project through a
# symlink, which is neither read nor written.

die() {
  printf 'settings.sh: %s\n' "$*" >&2
  exit 2
}

command -v jq >/dev/null 2>&1 || die "missing required tool: jq"
usage="usage: settings.sh plan|apply <root> [--allow-merge]"
case "${1:-}:$#:${3:-}" in
  plan:2: | apply:2: | plan:3:--allow-merge | apply:3:--allow-merge) ;;
  *) die "$usage" ;;
esac
mode=$1
root=$2
allow_merge=false
[ "$#" -eq 2 ] || allow_merge=true
[ -d "$root" ] || die "not a folder: $root"

here=$(dirname -- "$0")
# shellcheck source=plugins/dev-workflow/scripts/setup/atomic.sh
. "$here/atomic.sh"
# shellcheck source=plugins/dev-workflow/scripts/setup/json.sh
. "$here/json.sh"
# shellcheck source=plugins/dev-workflow/scripts/setup/paths.sh
. "$here/paths.sh"

MERGE_RULE='Bash(gh pr merge *)'
settings=$root/.claude/settings.json
local_settings=$root/.claude/settings.local.json
[ ! -e "$root/.claude" ] || [ -d "$root/.claude" ] || die "not a folder: $root/.claude"
path_check "$root" .claude/settings.json || exit 2

work=$(mktemp -d "${TMPDIR:-/tmp}/settings.XXXXXX") || die "cannot make a temp folder"
trap 'rm -rf "$work"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

report() { # <path> <action> [detail]
  jq -cn --arg p "$1" --arg a "$2" --arg d "${3:-}" \
    '{path: $p, action: $a} + (if $d == "" then {} else {detail: $d} end)'
}

# plan_file <file> <name> <filter> [jq options]: sets the action, or exits 2.
plan_file() {
  _plan_file=$1
  _plan_name=$2
  shift 2
  json_edit "$_plan_file" "$work/$_plan_name" "$@"
  case $? in
    0) if [ -e "$_plan_file" ]; then echo update; else echo create; fi ;;
    1) echo keep ;;
    *) return 2 ;;
  esac
}

# Every file is planned before any is written.
settings_action=$(plan_file "$settings" settings '
  .attribution = ((.attribution | if type == "object" then . else {} end)
    + {commit: "", pr: "", sessionUrl: false})') || exit 2

if [ "$allow_merge" = true ]; then
  # shellcheck disable=SC2016 # The dollars are jq's.
  local_action=$(plan_file "$local_settings" local '
    if (.permissions // {} | type) != "object" or (.permissions.allow // [] | type) != "array"
    then error("permissions.allow has to be a list") else . end
    | .permissions.allow = ((.permissions.allow // []) | if any(. == $rule) then . else . + [$rule] end)
  ' --arg rule "$MERGE_RULE") || exit 2
  local_detail=
  if [ "$local_action" != keep ] && git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1 &&
    ! git -C "$root" check-ignore -q .claude/settings.local.json 2>/dev/null; then
    local_detail="git doesn't ignore it: add .claude/settings.local.json to .gitignore, so it isn't committed"
  fi
fi

report .claude/settings.json "$settings_action"
[ "$allow_merge" = false ] || report .claude/settings.local.json "$local_action" "$local_detail"

[ "$mode" = apply ] || exit 0
if [ "$settings_action" != keep ] || { [ "$allow_merge" = true ] && [ "$local_action" != keep ]; }; then
  mkdir -p -- "$root/.claude" || die "cannot create: $root/.claude"
fi
if [ "$settings_action" != keep ]; then
  atomic_write "$settings" <"$work/settings" || exit 2
fi
if [ "$allow_merge" = true ] && [ "$local_action" != keep ]; then
  atomic_write "$local_settings" <"$work/local" || exit 2
fi
