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

# shellcheck source=tests/lib/live.sh
. "$ROOT/tests/lib/live.sh"

# Run from inside a session, these would tie the new ones to it.
unset CLAUDECODE CLAUDE_CODE_ENTRYPOINT CLAUDE_CODE_SESSION_ID CLAUDE_CODE_CHILD_SESSION \
  CLAUDE_CODE_SESSION_ATTENDED CLAUDE_PID CLAUDE_EFFORT CLAUDE_CODE_MESSAGING_SOCKET \
  CLAUDE_CODE_MESSAGING_TOKEN CLAUDE_AGENT_SDK_VERSION CLAUDE_CODE_EMIT_SESSION_STATE_EVENTS \
  CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_ROOT

reset='npm run db:reset'
chained='npm test && git merge --no-edit feature'
no_verify='git commit --no-verify --allow-empty -m "chore: skip the hooks"'
workflow_prompt='Use the Write tool to create .github/workflows/ci.yml, containing exactly this one line: on: pull_request. If it is blocked, run nothing else: just say so.'

echo "live-hooks: $(claude --version), model $model"

# --- "ask" on a database reset, in every mode that can run without a person

repo=$(live_repo with-project)
run_command "$repo" "$plugin" "$reset"
record 'reset: -p default' ask no "$(exists "$repo" reset-ran)"

repo=$(live_repo with-project)
run_command "$repo" "$plugin" "$reset" --allowedTools Bash
record 'reset: -p default, Bash allowed' ask no "$(exists "$repo" reset-ran)"

repo=$(live_repo with-project)
run_command "$repo" "$plugin" "$reset" --permission-mode dontAsk --allowedTools Bash
record 'reset: dontAsk, Bash allowed' ask no "$(exists "$repo" reset-ran)"

repo=$(live_repo with-project)
run_command "$repo" "$plugin" "$reset" --permission-mode auto
record 'reset: auto' ask no "$(exists "$repo" reset-ran)"

repo=$(live_repo with-project)
run_command "$repo" "$plugin" "$reset" --permission-mode auto --allowedTools Bash
record 'reset: auto, Bash rule (dropped by auto)' ask no "$(exists "$repo" reset-ran)"

# A rule in the project's own settings, which -p ignores in a folder nobody trusted.
repo=$(live_repo with-project)
in_temp "$repo"
printf '{"permissions": {"allow": ["Bash(npm run db:reset)"]}}\n' >"$repo/.claude/settings.json"
run_command "$repo" "$plugin" "$reset"
record 'reset: allow rule in the project' ask no "$(exists "$repo" reset-ran)"

# A project's hook that says yes to anything asked. The control is the same hook, asked the
# same way, in a repo with no project file: it shows that the hook can approve a prompt, so
# that the two after it mean something.
repo=$(live_repo without-project)
add_say_yes "$repo"
run_command "$repo" "$plugin" "$reset"
record 'control: PermissionRequest hook, no project' none yes "$(exists "$repo" reset-ran)"
echo "  the hook ran: $(exists "$repo" say-yes-ran)"

repo=$(live_repo with-project)
add_say_yes "$repo"
run_command "$repo" "$plugin" "$reset"
record 'reset: PermissionRequest hook says yes' ask no "$(exists "$repo" reset-ran)"
echo "  the hook ran: $(exists "$repo" say-yes-ran)"

repo=$(live_repo with-project)
add_say_yes "$repo"
run_command "$repo" "$plugin" "$reset" --allowedTools Bash
record 'reset: same hook, Bash allowed' ask no "$(exists "$repo" reset-ran)"
echo "  the hook ran: $(exists "$repo" say-yes-ran)"

# --- What's denied outright, with the tool allowed

repo=$(live_repo with-project)
run_command "$repo" "$plugin" "$chained" --allowedTools Bash
record 'chained merge' deny no "$(exists "$repo" test-ran)"
[ "$(merged "$repo")" = no ] || echo 'live-hooks: the feature branch was merged all the same'

repo=$(live_repo with-project)
run_command "$repo" "$plugin" "$no_verify" --allowedTools Bash
record 'git commit --no-verify' deny no "$(committed "$repo")"

repo=$(live_repo with-project)
session "$repo" "$plugin" "$workflow_prompt" --tools Write --allowedTools Write
record 'a workflow with a per-PR trigger' ask no "$(exists "$repo" .github/workflows/ci.yml)"

# --- Ordinary commands still run, and the session-start check is heard

repo=$(live_repo with-project)
run_command "$repo" "$plugin" 'touch plain-ran' --allowedTools Bash
record 'an ordinary command' none yes "$(exists "$repo" plain-ran)"
case $start_said in
  *'dev-workflow: '*'git config core.hooksPath .githooks'*) echo 'session start: said the git hooks are off' ;;
  *)
    echo "session start: FAILED: it said: $start_said"
    failures=$((failures + 1))
    ;;
esac

# --- A broken script blocks

repo=$(live_repo with-project)
plugin_copy
printf 'exit 3\n' >"$copy/scripts/hook-bash.sh"
run_command "$repo" "$copy" 'touch broken-ran' --allowedTools Bash
record 'a script that fails' failed no "$(exists "$repo" broken-ran)"

repo=$(live_repo with-project)
plugin_copy
mv "$copy/scripts/hook-bash.sh" "$copy/scripts/hook-bash.gone"
run_command "$repo" "$copy" 'touch broken-ran' --allowedTools Bash
record 'a script that is missing' failed no "$(exists "$repo" broken-ran)"

repo=$(live_repo with-project)
plugin_copy
printf 'sleep 60\n' >"$copy/scripts/hook-bash.sh"
jq '(.hooks.PreToolUse[].hooks[].timeout) = 1' "$plugin/hooks/hooks.json" >"$copy/hooks/hooks.json"
run_command "$repo" "$copy" 'touch broken-ran' --allowedTools Bash
record 'a script that times out' failed no "$(exists "$repo" broken-ran)"

# --- A copy that lost its modes still works

repo=$(live_repo with-project)
plugin_copy
find "$copy" -type f -exec chmod a-x {} +
run_command "$repo" "$copy" "$no_verify" --allowedTools Bash
record 'git commit --no-verify, no execute bits' deny no "$(committed "$repo")"

# --- The same in a repo without a project file: nothing in the way, and nothing said

repo=$(live_repo without-project)
run_command "$repo" "$plugin" "$reset" --allowedTools Bash
record 'no project file: reset' none yes "$(exists "$repo" reset-ran)"
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
record 'no project file: a per-PR workflow' none yes "$(exists "$repo" .github/workflows/ci.yml)"

echo "live-hooks: $case_number sessions, \$$total_cost spent, $passed ok, $not_exercised not exercised, $failures failed"
[ "$failures" -eq 0 ]
