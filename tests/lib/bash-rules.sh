#!/bin/sh
# The fixture for tests of the rules on Bash commands, which are tables of commands and the
# decision each gets, run through the real hook in a real repo. Source this after assert.sh
# and hook.sh, with ROOT set; don't run it. Each test file has its own copy of the repo, on
# a work branch, so it can move its branches about.
#
# shellcheck disable=SC2034,SC2154 # The tests read these, and hook.sh sets _hook_field.

plugin="$ROOT/plugins/dev-workflow"
hook="$plugin/scripts/hook-bash.sh"

unset HOOK_PATH

# A path with a space, because a project can live in one.
repo="$(tmp_dir)/a b/repo"
new_repo "$repo"
mkdir -p "$repo/.claude" "$repo/sub"
cat >"$repo/.claude/dev-workflow.json" <<'JSON'
{
  "commands": { "check": "npm run check", "verify": "scripts/verify" },
  "testCommands": ["npx vitest"],
  "databaseResetCommands": ["npm run db:reset"]
}
JSON
git -C "$repo" commit -q --allow-empty -m 'chore: start'
git -C "$repo" branch feat/1-x
git -C "$repo" branch feat/2-y
CLAUDE_PROJECT_DIR=$repo
export CLAUDE_PROJECT_DIR
cd "$repo" || exit 1

on_branch() {
  git -C "$repo" symbolic-ref HEAD "refs/heads/$1" || _assert_fail "could not switch to $1"
}

# rule <deny|ask|none> <command> [text the reason must hold]
#
# It runs the hook once for both, as this table is long enough to slow every push.
rule() {
  _rule_input=$(bash_input "$2")
  _hook_run "$hook" "$_rule_input" || _assert_fail "the hook failed for: $2"
  _rule_decision=none
  if [ -n "$_hook_output" ]; then
    _hook_read_decision permissionDecision || _assert_fail "no readable decision for: $2"
    _rule_decision=$_hook_field
  fi
  [ "$_rule_decision" = "$1" ] || _assert_fail "expected $1, got \"$_rule_decision\" for: $2"
  if [ -n "${3:-}" ]; then
    _hook_read_decision permissionDecisionReason || _assert_fail "no readable reason for: $2"
    assert_contains "$_hook_field" "$3"
  fi
}

# rule_stdin <deny|ask|none> [text the reason must hold]: the same, with the command on
# stdin. Holding one in a command substitution would make the shell parse its quotes.
rule_stdin() {
  rule "$1" "$(cat)" "${2:-}"
}

on_branch feat/1-x
