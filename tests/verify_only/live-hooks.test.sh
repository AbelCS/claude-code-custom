#!/bin/sh
# Runs real Claude Code sessions with the plugin, each in its own temp repo, and records
# what the hooks did to real commands. docs/hook-behaviour.md holds the results.
#
# It costs a little, so it lives here and not in scripts/check. What counts as evidence is
# what happened in the repo: a marker file the command would have written, a commit, a
# merge. A permission mode that denies everything would look like a hook working, so the
# blocked cases allow the tool outright, and the same commands run in a repo with no
# project file to show that they can.
#
# DW_SKIP_LIVE=1 skips it. DW_LIVE_MODEL picks the model, which should be a cheap one.

if [ "${DW_SKIP_LIVE:-}" = 1 ]; then
  echo 'live-hooks: skipped, because DW_SKIP_LIVE=1'
  exit 0
fi
for needed in claude npm; do
  if ! command -v "$needed" >/dev/null 2>&1; then
    echo "live-hooks: skipped, because $needed isn't on the PATH"
    exit 0
  fi
done

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
# shellcheck source=tests/lib/assert.sh
. "$ROOT/tests/lib/assert.sh"

plugin="$ROOT/plugins/dev-workflow"
model=${DW_LIVE_MODEL:-haiku}
budget_each=0.25
budget_total=1.50

# Run from inside a session, these would tie the new ones to it.
unset CLAUDECODE CLAUDE_CODE_ENTRYPOINT CLAUDE_CODE_SESSION_ID CLAUDE_CODE_CHILD_SESSION \
  CLAUDE_CODE_SESSION_ATTENDED CLAUDE_PID CLAUDE_EFFORT CLAUDE_CODE_MESSAGING_SOCKET \
  CLAUDE_CODE_MESSAGING_TOKEN CLAUDE_AGENT_SDK_VERSION CLAUDE_CODE_EMIT_SESSION_STATE_EVENTS \
  CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_ROOT

logs=$(tmp_dir)
case_number=0
total_cost=0
failures=0

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

# plugin_copy: prints a new copy of the plugin, for a case to break.
plugin_copy() {
  pc_copy="$(tmp_dir)/plugin"
  cp -R "$plugin" "$pc_copy" || _assert_fail "could not copy the plugin"
  printf '%s\n' "$pc_copy"
}

# session <repo> <plugin folder> <prompt> <claude option...>: one session, leaving what
# it did in these:
#   log, mode      its log, and the permission mode it says it ran in
#   tried          whether the model called a tool at all
#   decision       what the first PreToolUse hook decided: ask, deny, none or failed
#   start_said     what the session-start check printed
session() {
  se_repo=$1
  se_plugin=$2
  se_prompt=$3
  shift 3
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

# record <what> <decision expected> <effect expected: yes|no> <effect seen: yes|no>: a
# line of results. A model that never tried shows nothing, so that fails as well.
record() {
  if [ "$tried" != yes ]; then
    outcome='FAILED: the model never tried, so this shows nothing'
  elif [ "$4" != "$3" ]; then
    outcome="FAILED: the effect was $4, not $3"
    if [ "$2" = ask ] && [ "$4" = yes ]; then
      outcome="FAILED: \"ask\" PASSED WITHOUT A PERSON"
    fi
  elif [ "$decision" != "$2" ]; then
    outcome="FAILED: the hook's decision was $decision, not $2"
  else
    outcome=ok
  fi
  printf '%-44s mode=%-18s hook=%-7s ran=%-4s %s\n' "$1" "$mode" "$decision" "$4" "$outcome"
  if [ "$outcome" != ok ]; then
    failures=$((failures + 1))
    # The logs go with the temp folder, and this is what explains a failure.
    jq -c 'select(.type == "assistant") | .message.content[]? | select(.type == "tool_use") | .input' "$log"
  fi
}

# exists <path>: prints yes or no.
exists() {
  if [ -e "$1" ]; then echo yes; else echo no; fi
}

# merged <repo>: whether the feature branch is in HEAD.
merged() {
  if git -C "$1" merge-base --is-ancestor feature HEAD; then echo yes; else echo no; fi
}

# committed <repo>: whether the work branch has moved from main.
committed() {
  if [ "$(git -C "$1" rev-parse HEAD)" != "$(git -C "$1" rev-parse main)" ]; then echo yes; else echo no; fi
}

reset='npm run db:reset'
chained='npm test && git merge --no-edit feature'
no_verify='git commit --no-verify --allow-empty -m "chore: skip the hooks"'
workflow_prompt='Use the Write tool to create .github/workflows/ci.yml, containing exactly this one line: on: pull_request. If it is blocked, run nothing else: just say so.'

echo "live-hooks: $(claude --version), model $model"

# --- "ask" on a database reset, in every mode that can run without a person

repo=$(live_repo with-project)
run_command "$repo" "$plugin" "$reset"
record 'reset: -p default' ask no "$(exists "$repo/reset-ran")"

repo=$(live_repo with-project)
run_command "$repo" "$plugin" "$reset" --allowedTools Bash
record 'reset: -p default, Bash allowed' ask no "$(exists "$repo/reset-ran")"

repo=$(live_repo with-project)
run_command "$repo" "$plugin" "$reset" --permission-mode dontAsk --allowedTools Bash
record 'reset: dontAsk, Bash allowed' ask no "$(exists "$repo/reset-ran")"

repo=$(live_repo with-project)
run_command "$repo" "$plugin" "$reset" --permission-mode auto
record 'reset: auto' ask no "$(exists "$repo/reset-ran")"

repo=$(live_repo with-project)
run_command "$repo" "$plugin" "$reset" --permission-mode auto --allowedTools Bash
record 'reset: auto, Bash allowed' ask no "$(exists "$repo/reset-ran")"

# With no checks of its own, on a fixed prompt, in a temp repo, with only the Bash tool.
repo=$(live_repo with-project)
run_command "$repo" "$plugin" "$reset" --permission-mode bypassPermissions
record 'reset: bypassPermissions' ask no "$(exists "$repo/reset-ran")"

# A rule in the project's own settings, which -p ignores in a folder nobody trusted.
repo=$(live_repo with-project)
printf '{"permissions": {"allow": ["Bash(npm run db:reset)"]}}\n' >"$repo/.claude/settings.json"
run_command "$repo" "$plugin" "$reset"
record 'reset: allow rule in the project' ask no "$(exists "$repo/reset-ran")"

# A project's hook that says yes to anything asked.
repo=$(live_repo with-project)
cat >"$repo/.claude/say-yes.sh" <<'SCRIPT'
printf '{"hookSpecificOutput": {"hookEventName": "PermissionRequest", "decision": {"behavior": "allow"}}}\n'
SCRIPT
cat >"$repo/.claude/settings.json" <<'JSON'
{"hooks": {"PermissionRequest": [{"matcher": "Bash", "hooks": [
  {"type": "command", "command": "sh", "args": [".claude/say-yes.sh"]}
]}]}}
JSON
run_command "$repo" "$plugin" "$reset" --allowedTools Bash
record 'reset: PermissionRequest hook says yes' ask no "$(exists "$repo/reset-ran")"

# --- What's denied outright, with the tool allowed

repo=$(live_repo with-project)
run_command "$repo" "$plugin" "$chained" --allowedTools Bash
record 'chained merge' deny no "$(exists "$repo/test-ran")"
[ "$(merged "$repo")" = no ] || echo 'live-hooks: the feature branch was merged all the same'

repo=$(live_repo with-project)
run_command "$repo" "$plugin" "$no_verify" --allowedTools Bash
record 'git commit --no-verify' deny no "$(committed "$repo")"

repo=$(live_repo with-project)
session "$repo" "$plugin" "$workflow_prompt" --tools Write --allowedTools Write
record 'a workflow with a per-PR trigger' ask no "$(exists "$repo/.github/workflows/ci.yml")"

# --- Ordinary commands still run, and the session-start check is heard

repo=$(live_repo with-project)
run_command "$repo" "$plugin" 'touch plain-ran' --allowedTools Bash
record 'an ordinary command' none yes "$(exists "$repo/plain-ran")"
case $start_said in
  *'dev-workflow: '*'git config core.hooksPath .githooks'*) echo 'session start: said the git hooks are off' ;;
  *)
    echo "session start: FAILED: it said: $start_said"
    failures=$((failures + 1))
    ;;
esac

# --- A broken script blocks

repo=$(live_repo with-project)
copy=$(plugin_copy)
printf 'exit 3\n' >"$copy/scripts/hook-bash.sh"
run_command "$repo" "$copy" 'touch broken-ran' --allowedTools Bash
record 'a script that fails' failed no "$(exists "$repo/broken-ran")"

repo=$(live_repo with-project)
copy=$(plugin_copy)
mv "$copy/scripts/hook-bash.sh" "$copy/scripts/hook-bash.gone"
run_command "$repo" "$copy" 'touch broken-ran' --allowedTools Bash
record 'a script that is missing' failed no "$(exists "$repo/broken-ran")"

repo=$(live_repo with-project)
copy=$(plugin_copy)
printf 'sleep 60\n' >"$copy/scripts/hook-bash.sh"
jq '(.hooks.PreToolUse[].hooks[].timeout) = 1' "$plugin/hooks/hooks.json" >"$copy/hooks/hooks.json"
run_command "$repo" "$copy" 'touch broken-ran' --allowedTools Bash
record 'a script that times out' failed no "$(exists "$repo/broken-ran")"

# --- A copy that lost its modes still works

repo=$(live_repo with-project)
copy=$(plugin_copy)
find "$copy" -type f -exec chmod a-x {} +
run_command "$repo" "$copy" "$no_verify" --allowedTools Bash
record 'git commit --no-verify, no execute bits' deny no "$(committed "$repo")"

# --- The same in a repo without a project file: nothing in the way, and nothing said

repo=$(live_repo without-project)
run_command "$repo" "$plugin" "$reset" --allowedTools Bash
record 'no project file: reset' none yes "$(exists "$repo/reset-ran")"
if [ -n "$start_said" ]; then
  echo "session start: FAILED: it said this with no project file: $start_said"
  failures=$((failures + 1))
fi

repo=$(live_repo without-project)
run_command "$repo" "$plugin" "$chained" --allowedTools Bash
record 'no project file: chained merge' none yes "$(merged "$repo")"

repo=$(live_repo without-project)
run_command "$repo" "$plugin" "$no_verify" --allowedTools Bash
record 'no project file: git commit --no-verify' none yes "$(committed "$repo")"

repo=$(live_repo without-project)
session "$repo" "$plugin" "$workflow_prompt" --tools Write --allowedTools Write
record 'no project file: a per-PR workflow' none yes "$(exists "$repo/.github/workflows/ci.yml")"

echo "live-hooks: $case_number sessions, \$$total_cost spent, $failures failed"
[ "$failures" -eq 0 ]
