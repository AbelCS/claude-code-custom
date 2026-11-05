#!/bin/sh
# Usage: project-file.sh write <root> <answers.json>
#        project-file.sh validate <file>
#        project-file.sh existing-ci <root>
#
#   write        merges the answers into <root>/.claude/dev-workflow.json, then
#                generates <root>/.githooks/dev-workflow.env from it. Prints one JSON
#                line per file: { "path": str, "action": "create|update|keep" }
#   validate     checks a project file against skills/setup/references/
#                project-file.schema.json, printing each problem
#   existing-ci  prints each workflow in <root>/.github/workflows/ with a per-PR
#                trigger, or one the hooks can't read, one path per line, leaving out
#                those already in ciAllowlist, so they can be offered for it
#
# The answers are a JSON object of the project file's own fields, such as stack,
# hasScreens, defaultBranch, commands, testCommands, databaseResetCommands and
# ciAllowlist. A field they leave out keeps what the file has, and commands merge
# command by command. schemaVersion and pluginVersion are setup's, and managed is the
# ledger's, so answers holding them are refused. Each stack's reset commands, from
# stacks/<stack>.resets, or $DW_STACKS_DIR to test, are added to databaseResetCommands.
#
# The file is checked before anything is written, and not rewritten if nothing in it
# changed. Known fields come in the schema's order, the ledger last. The env file sets
# all four of the git hooks' settings, lists as newline-separated lines and the
# formatters as glob|command, each value quoted for sh.
#
# Exits 1 when validate finds problems, and 2 on any other error, writing nothing.
# Neither file is read or written through a symlink, nor in a folder that leads out
# of the project through one.

die() {
  printf 'project-file.sh: %s\n' "$*" >&2
  exit 2
}

command -v jq >/dev/null 2>&1 || die "missing required tool: jq"

here=$(dirname -- "$0")
plugin=$here/../..
schema=$plugin/skills/setup/references/project-file.schema.json
stacks=${DW_STACKS_DIR:-$plugin/stacks}
[ -f "$schema" ] || die "schema not found: $schema"

# is_object <file>: whether it's one JSON object.
is_object() {
  jq -e -s 'length == 1 and (.[0] | type == "object")' "$1" >/dev/null 2>&1
}

# problems <file>: prints what's wrong with it, if anything.
problems() {
  if ! is_object "$1"; then
    echo "$1 isn't valid JSON holding one object"
    return
  fi
  jq -r --slurpfile schema "$schema" -f "$here/schema-check.jq" "$1"
}

validate() {
  [ -f "$1" ] && [ -r "$1" ] || die "cannot read: $1"
  found=$(problems "$1") || die "cannot check: $1"
  [ -n "$found" ] || return 0
  printf '%s is not a valid project file:\n' "$1" >&2
  printf '%s\n' "$found" | sed 's/^/  /' >&2
  return 1
}

# existing_ci <root>
existing_ci() {
  [ -d "$1" ] || die "not a folder: $1"
  # shellcheck source=plugins/dev-workflow/skills/setup/templates/githooks/dw-lib.sh
  . "$plugin/skills/setup/templates/githooks/dw-lib.sh"
  allowlist=
  if [ -e "$1/.claude/dev-workflow.json" ]; then
    allowlist=$(jq -r '(.ciAllowlist // [])[] | strings' "$1/.claude/dev-workflow.json" 2>/dev/null) ||
      die "cannot read ciAllowlist in: $1/.claude/dev-workflow.json"
  fi
  for file in "$1"/.github/workflows/*; do
    [ -f "$file" ] || continue
    path=.github/workflows/${file##*/}
    dw_is_workflow "$path" || continue
    dw_in_lines "$path" "$allowlist" && continue
    content=$(cat -- "$file") || die "cannot read: $file"
    triggers=$(dw_ci_triggers "$content") || triggers='?'
    [ -z "$triggers" ] || printf '%s\n' "$path"
  done
}

case "${1:-}:$#" in
  validate:2)
    validate "$2"
    exit
    ;;
  existing-ci:2)
    existing_ci "$2"
    exit 0
    ;;
  write:3) ;;
  *) die "usage: project-file.sh write <root> <answers.json> | validate <file> | existing-ci <root>" ;;
esac

# --- write

root=$2
answers=$3
[ -d "$root" ] || die "not a folder: $root"
[ -f "$answers" ] && [ -r "$answers" ] || die "cannot read: $answers"
is_object "$answers" || die "the answers aren't valid JSON holding one object: $answers"
owned=$(jq -r '[keys[] | select(IN("schemaVersion", "pluginVersion", "managed"))] | join(", ")' "$answers")
[ -z "$owned" ] || die "the answers can't set $owned, which setup keeps itself"

pf=$root/.claude/dev-workflow.json
env_file=$root/.githooks/dev-workflow.env
# shellcheck source=plugins/dev-workflow/scripts/setup/paths.sh
. "$here/paths.sh"
path_check "$root" .claude/dev-workflow.json .githooks/dev-workflow.env || exit 2
for f in "$pf" "$env_file"; do
  [ ! -L "$f" ] || die "a symlink; not reading or writing through it: $f"
done
version=$(jq -r '.version | strings' "$plugin/.claude-plugin/plugin.json") || die "cannot read the plugin's version"
current='{}'
if [ -e "$pf" ]; then
  is_object "$pf" || die "$pf isn't valid JSON holding one object: fix it, or move it away and run setup again"
  current=$(cat -- "$pf") || die "cannot read: $pf"
fi

# shellcheck source=plugins/dev-workflow/scripts/setup/atomic.sh
. "$here/atomic.sh"
# shellcheck source=plugins/dev-workflow/scripts/setup/json.sh
. "$here/json.sh"
work=$(mktemp -d "${TMPDIR:-/tmp}/project-file.XXXXXX") || die "cannot make a temp folder"
trap 'rm -rf "$work"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

# merge [resets]: the new file, with the stacks' reset commands added if given.
merge() {
  printf '%s\n' "$current" | jq --slurpfile a "$answers" --arg v "$version" --argjson resets "${1:-[]}" '
    . as $old | $a[0] as $new
    | {schemaVersion: null, pluginVersion: null, stack: null, hasScreens: null,
       defaultBranch: null, commands: null, testCommands: null,
       databaseResetCommands: null, ciAllowlist: null}
      + $old + $new
    | del(.managed) + {schemaVersion: 1, pluginVersion: $v, managed: $old.managed}
    | if ($old.commands | type) == "object" and ($new.commands | type) == "object"
      then .commands = $old.commands + $new.commands else . end
    | if ($resets | length) > 0 then
        .databaseResetCommands = (reduce ((.databaseResetCommands // [])[], $resets[]) as $c
          ([]; if index([$c]) then . else . + [$c] end))
      else . end
    | with_entries(select(.value != null))'
}

merge >"$work/merged" || die "cannot merge the answers: $answers"
validate "$work/merged" 2>"$work/problems" || {
  sed "s#^$work/merged#the project file, with these answers,#" "$work/problems" >&2
  exit 2
}

# Each stack's reset commands. The names were checked above, so they're safe in a path.
resets=$(jq -r '(.stack // [])[]' "$work/merged" | while IFS= read -r name; do
  [ ! -f "$stacks/$name.resets" ] || sed -e 's/[[:space:]]*$//' -e '/^$/d' -e '/^#/d' "$stacks/$name.resets"
done | jq -R . | jq -s -c .) || die "cannot read the stacks' reset commands in: $stacks"
if [ "$resets" != '[]' ]; then
  merge "$resets" >"$work/merged" || die "cannot merge the answers: $answers"
  validate "$work/merged" 2>/dev/null || die "a stack's reset commands aren't valid: $stacks"
fi

# --- the env file, from the merged file

{
  echo '# Generated by the dev-workflow setup skill from .claude/dev-workflow.json. Edit'
  echo '# that file instead, then run the setup skill again.'
  jq -r '
    "DW_DEFAULT_BRANCH=\(.defaultBranch // "main" | @sh)",
    "DW_CHECK=\(.commands.check | @sh)",
    "DW_CI_ALLOWLIST=\(.ciAllowlist // [] | join("\n") | @sh)",
    "DW_FORMATTERS=\(.commands.formatCheckStaged // [] | map("\(.glob)|\(.command)") | join("\n") | @sh)"
  ' "$work/merged"
} >"$work/env" || die "cannot generate the env file"

report() { jq -cn --arg p "$1" --arg a "$2" '{path: $p, action: $a}'; }

# shellcheck disable=SC2016 # The dollars are jq's.
json_edit "$pf" "$work/pf" '$new[0]' --slurpfile new "$work/merged"
case $? in
  0) if [ -e "$pf" ]; then pf_action=update; else pf_action=create; fi ;;
  1) pf_action=keep ;;
  *) exit 2 ;;
esac
if [ ! -e "$env_file" ]; then
  env_action=create
elif cmp -s "$env_file" "$work/env"; then
  env_action=keep
else
  env_action=update
fi

if [ "$pf_action" != keep ]; then
  mkdir -p -- "$root/.claude" || die "cannot create: $root/.claude"
  atomic_write "$pf" <"$work/pf" || exit 2
fi
if [ "$env_action" != keep ]; then
  mkdir -p -- "$root/.githooks" || die "cannot create: $root/.githooks"
  atomic_write "$env_file" <"$work/env" || exit 2
fi
report .claude/dev-workflow.json "$pf_action"
report .githooks/dev-workflow.env "$env_action"
