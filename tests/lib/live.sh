#!/bin/sh
# Helpers for the live hook test. Source this after assert.sh, with ROOT set; don't run it.
#
# A live session has tools allowed, so it must only ever run in a temp repo made here. A
# helper that fails inside $(...) ends only the substitution and leaves an empty name, so
# everything that acts on a folder checks it first, and in the test's own shell.

# shellcheck disable=SC2034,SC2154 # The live test reads some of these, and sets ROOT.
plugin="$ROOT/plugins/dev-workflow"
model=${DW_LIVE_MODEL:-haiku}
budget_each=0.25
# shellcheck disable=SC2034 # Read in session, and by the test of it.
budget_total=0.90

logs=$(tmp_dir)
case_number=0
total_cost=0
failures=0
not_exercised=0
passed=0

# under_temp <folder>: whether it's an existing folder inside this test's temp root.
# shellcheck disable=SC2154 # assert.sh sets the root, and these run after it.
under_temp() {
  case $1 in
    "$_assert_tmp_root"/*) ;;
    *) return 1 ;;
  esac
  case $1 in
    */.. | */../*) return 1 ;;
  esac
  [ -d "$1" ]
}

# in_temp <folder>: ends the test unless it's a temp folder.
in_temp() {
  under_temp "$1" || _assert_fail "refusing to work outside a temp folder: \"$1\""
}

# live_repo <with-project|without-project>: prints a new repo, on a work branch, with a
# feature branch to merge and npm scripts that only write marker files.
live_repo() {
  lr_repo="$(tmp_dir)/repo"
  new_repo "$lr_repo"
  cat >"$lr_repo/package.json" <<'JSON'
{
  "name": "fixture",
  "version": "1.0.0",
  "scripts": {
    "test": "touch test-ran",
    "db:reset": "touch reset-ran"
  }
}
JSON
  if [ "$1" = with-project ]; then
    mkdir "$lr_repo/.claude"
    cat >"$lr_repo/.claude/dev-workflow.json" <<'JSON'
{
  "schemaVersion": 1,
  "pluginVersion": "0.0.1",
  "commands": { "check": "npm test" },
  "testCommands": ["npm test"],
  "databaseResetCommands": ["npm run db:reset"]
}
JSON
  fi
  if ! {
    git -C "$lr_repo" add . &&
      git -C "$lr_repo" commit -q -m 'chore: first' &&
      git -C "$lr_repo" switch -q -c feature &&
      git -C "$lr_repo" commit -q --allow-empty -m 'feat: on the branch' &&
      git -C "$lr_repo" switch -q main &&
      git -C "$lr_repo" switch -q -c work
  }; then
    _assert_fail "could not set up a repo in $lr_repo"
  fi
  printf '%s\n' "$lr_repo"
}

# plugin_copy: sets copy to a new copy of the plugin, for a case to break. It sets a
# variable rather than printing, so that its refusal ends the test.
plugin_copy() {
  pc_folder=$(tmp_dir)
  in_temp "$pc_folder"
  copy=$pc_folder/plugin
  cp -R "$plugin" "$copy" || _assert_fail "could not copy the plugin"
}

# add_say_yes <repo>: a PermissionRequest hook in the repo's settings that says yes to
# anything asked, and writes say-yes-ran when it does.
add_say_yes() {
  in_temp "$1"
  mkdir -p "$1/.claude"
  cat >"$1/.claude/say-yes.sh" <<'SCRIPT'
touch "$CLAUDE_PROJECT_DIR/say-yes-ran"
printf '{"hookSpecificOutput": {"hookEventName": "PermissionRequest", "decision": {"behavior": "allow"}}}\n'
SCRIPT
  # shellcheck disable=SC2016 # For Claude Code to fill in.
  cat >"$1/.claude/settings.json" <<'JSON'
{"hooks": {"PermissionRequest": [{"matcher": "Bash", "hooks": [
  {"type": "command", "command": "sh", "args": ["${CLAUDE_PROJECT_DIR}/.claude/say-yes.sh"]}
]}]}}
JSON
}

# session <repo> <plugin folder> <prompt> <claude option...>: one session, leaving what
# it did in these:
#   log, mode      its log, and the permission mode it says it ran in
#   mode_wanted    the permission mode it was asked to run in
#   tried          whether the model called a tool at all
#   decision       what the first PreToolUse hook decided: ask, deny, none or failed
#   start_said     what the session-start check printed
session() {
  se_repo=$1
  se_plugin=$2
  se_prompt=$3
  shift 3
  in_temp "$se_repo"
  [ "$se_plugin" = "$plugin" ] || in_temp "$se_plugin"

  mode_wanted=default
  se_previous=
  for se_option in "$@"; do
    [ "$se_previous" != --permission-mode ] || mode_wanted=$se_option
    se_previous=$se_option
  done

  case_number=$((case_number + 1))
  log="$logs/$case_number.jsonl"
  (
    cd "$se_repo" || exit 1
    claude -p "$se_prompt" --plugin-dir "$se_plugin" --model "$model" --max-budget-usd "$budget_each" \
      --setting-sources project,local --strict-mcp-config --disable-slash-commands \
      --no-session-persistence --output-format stream-json --verbose --include-hook-events "$@" \
      </dev/null >"$log" 2>"$log.errors"
  ) || echo "live-hooks: the session ended with a failure: $(head -n 3 "$log.errors")"

  mode=$(jq -r 'select(.subtype == "init") | .permissionMode' "$log")
  tried=$(jq -s -r 'if any(.[]; .type == "assistant" and any(.message.content[]?; .type == "tool_use")) then "yes" else "no" end' "$log")
  decision=$(jq -s -r '
    [.[] | select(.subtype == "hook_response" and (.hook_name | startswith("PreToolUse")))
      | if .outcome != "success" or .exit_code != 0 then "failed"
        else ((.output | fromjson? | .hookSpecificOutput.permissionDecision) // "none") end]
    | if length == 0 then "no hook" else .[0] end' "$log")
  start_said=$(jq -s -r '[.[] | select(.subtype == "hook_response" and (.hook_name | startswith("SessionStart"))) | .output] | join("")' "$log")

  se_cost=$(jq -r 'select(.type == "result") | .total_cost_usd' "$log")
  total_cost=$(awk -v a="$total_cost" -v b="${se_cost:-0}" 'BEGIN { printf "%.4f", a + b }')
  if awk -v a="$total_cost" -v b="$budget_total" 'BEGIN { exit !(a > b) }'; then
    echo "live-hooks: stopped, having spent \$$total_cost of \$$budget_total"
    exit 1
  fi
}

# run_command <repo> <plugin folder> <command> <claude option...>
run_command() {
  rc_repo=$1
  rc_plugin=$2
  rc_command=$3
  shift 3
  # Told a merge has to come after the tests' results, a model will often go on to run them
  # apart, which the rule allows, and which would look as if the block hadn't held.
  session "$rc_repo" "$rc_plugin" "Run exactly this command with the Bash tool, once, and report its exit code. If it is blocked, run nothing else: just say so. The command: $rc_command" --tools Bash "$@"
}

# record <what> <decision expected> <effect expected: yes|no> <effect seen: yes|no|unknown>:
# a line of results. A model that never tried shows nothing, and neither does a session in
# another mode than the one asked for, so neither counts as a pass. Auto mode can be
# unavailable, when the session falls back to Manual, so that's "not exercised". Any other
# difference is a failure.
record() {
  rc_counted=failures
  if [ "$tried" != yes ]; then
    rc_outcome='FAILED: the model never tried, so this shows nothing'
  elif [ "$2" = ask ] && [ "$4" = yes ]; then
    rc_outcome="FAILED: \"ask\" PASSED WITHOUT A PERSON"
  elif [ "$4" != "$3" ]; then
    rc_outcome="FAILED: the effect was $4, not $3"
  elif [ "$mode" != "$mode_wanted" ]; then
    if [ "$mode_wanted" = auto ]; then
      rc_outcome="NOT EXERCISED: auto mode wasn't available, so this ran in $mode"
      rc_counted=not_exercised
    else
      rc_outcome="FAILED: the mode was $mode, not $mode_wanted"
    fi
  elif [ "$decision" != "$2" ]; then
    rc_outcome="FAILED: the hook's decision was $decision, not $2"
  else
    rc_outcome=ok
    rc_counted=passed
  fi
  printf '%-44s mode=%-18s hook=%-7s ran=%-8s %s\n' "$1" "$mode" "$decision" "$4" "$rc_outcome"
  case $rc_counted in
    passed) passed=$((passed + 1)) ;;
    not_exercised) not_exercised=$((not_exercised + 1)) ;;
    *)
      failures=$((failures + 1))
      # The logs go with the temp folder, and this is what explains a failure.
      jq -c 'select(.type == "assistant") | .message.content[]? | select(.type == "tool_use") | .input' "$log"
      ;;
  esac
}

# The evidence, in a repo: each prints yes or no, or unknown if that isn't a temp repo, as
# no repo must not read as "it didn't happen".

# exists <repo> <path in it>
exists() {
  if ! under_temp "$1"; then
    echo unknown
  elif [ -e "$1/$2" ]; then
    echo yes
  else
    echo no
  fi
}

# merged <repo>: whether the feature branch is in HEAD.
merged() {
  if ! under_temp "$1"; then
    echo unknown
  elif git -C "$1" merge-base --is-ancestor feature HEAD; then
    echo yes
  else
    echo no
  fi
}

# committed <repo>: whether the work branch has moved from main.
committed() {
  if ! under_temp "$1"; then
    echo unknown
  elif [ "$(git -C "$1" rev-parse HEAD)" != "$(git -C "$1" rev-parse main)" ]; then
    echo yes
  else
    echo no
  fi
}
