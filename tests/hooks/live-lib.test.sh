#!/bin/sh
# Tests the helpers the live hook test relies on, with a stand-in for claude, so that
# nothing here starts a session or spends anything. A live session has tools allowed, so
# it must never start outside a temp folder, and a row must never pass on no evidence.

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
# shellcheck source=tests/lib/assert.sh
. "$ROOT/tests/lib/assert.sh"
# shellcheck source=tests/lib/live.sh
. "$ROOT/tests/lib/live.sh"

# A stand-in that notes each start and where, and says it ran in STUB_MODE.
stub_bin=$(tmp_dir)
started="$(tmp_dir)/started"
cat >"$stub_bin/claude" <<STUB
#!/bin/sh
pwd >>'$started'
printf '{"type":"system","subtype":"init","permissionMode":"%s"}\n' "\${STUB_MODE:-default}"
printf '{"type":"assistant","message":{"content":[{"type":"tool_use","input":{"command":"x"}}]}}\n'
printf '{"type":"result","total_cost_usd":0.001}\n'
STUB
chmod +x "$stub_bin/claude"
PATH=$stub_bin:$PATH
export PATH

not_started() {
  [ ! -e "$started" ] || _assert_fail "claude was started in: $(cat "$started")"
}

# --- under_temp

folder=$(tmp_dir)
assert_exit 0 under_temp "$folder"
assert_exit 1 under_temp ''
assert_exit 1 under_temp "$PWD"
assert_exit 1 under_temp "$ROOT"
assert_exit 1 under_temp /
assert_exit 1 under_temp "$_assert_tmp_root"
assert_exit 1 under_temp "$folder/../../.."
assert_exit 1 under_temp "$folder/../../../somewhere"
assert_exit 1 under_temp "$folder/not-there"

# --- session refuses any folder but a temp one, before it starts anything

for bad_repo in '' "$PWD" "$ROOT" / "$folder/not-there" "$folder/../../.."; do
  assert_exit 1 session "$bad_repo" "$plugin" 'a prompt' --allowedTools Bash
  not_started
done
assert_exit 1 run_command '' "$plugin" 'ls' --allowedTools Bash
not_started
output=$(session '' "$plugin" 'a prompt' 2>&1)
assert_contains "$output" 'temp folder'

# The failure it's there for: a repo that couldn't be made leaves an empty name, and the
# test goes on to the session. It must stop there, and not count as a row.
# shellcheck disable=SC2016 # Text for another shell.
failing_setup='
  ROOT=$1
  . "$ROOT/tests/lib/assert.sh"
  . "$ROOT/tests/lib/live.sh"
  new_repo() { _assert_fail "could not create a repo"; }
  repo=$(live_repo with-project)
  run_command "$repo" "$plugin" "ls" --allowedTools Bash
  echo carried on
'
assert_exit 1 sh -c "$failing_setup" sh "$ROOT"
assert_not_contains "$(sh -c "$failing_setup" sh "$ROOT" 2>&1)" 'carried on'
not_started

# The plugin folder has to be the plugin or a copy of it in a temp folder.
good_repo=$(live_repo with-project)
assert_exit 0 test -n "$good_repo"
for bad_plugin in '' "$ROOT" /; do
  assert_exit 1 session "$good_repo" "$bad_plugin" 'a prompt'
  not_started
done

# In a temp repo, it runs there, and leaves what it found.
session "$good_repo" "$plugin" 'a prompt' --allowedTools Bash
assert_exit 0 test "$(cat "$started")" = "$(cd "$good_repo" && pwd)"
assert_exit 0 test "$mode" = default
assert_exit 0 test "$mode_wanted" = default
assert_exit 0 test "$tried" = yes
assert_exit 0 test "$case_number" -eq 1

STUB_MODE=auto
export STUB_MODE
session "$good_repo" "$plugin" 'a prompt' --permission-mode auto --allowedTools Bash
unset STUB_MODE
assert_exit 0 test "$mode" = auto
assert_exit 0 test "$mode_wanted" = auto

# --- plugin_copy refuses the same

plugin_copy
assert_exit 0 test -f "$copy/hooks/hooks.json"
assert_exit 0 under_temp "$copy"

outside=$(tmp_dir)
copy_outside() {
  # Whatever goes wrong in making the folder, the name it gives isn't a temp one.
  tmp_dir() { printf '%s\n' "$outside"; }
  _assert_tmp_root="$outside/elsewhere"
  plugin_copy
}
assert_exit 1 copy_outside
assert_exit 1 test -e "$outside/plugin"
copy_nowhere() {
  tmp_dir() { return 1; }
  plugin_copy
}
assert_exit 1 copy_nowhere
assert_exit 1 test -e /plugin

# --- Writing into a repo refuses the same

assert_exit 1 in_temp ''
assert_exit 1 in_temp "$ROOT"
assert_exit 0 in_temp "$good_repo"
assert_exit 1 add_say_yes ''
assert_exit 1 test -e "$PWD/.claude/say-yes.sh"

# --- The evidence: no repo is no evidence, so it can't read as "it didn't happen"

assert_exit 0 test "$(exists "$good_repo" package.json)" = yes
assert_exit 0 test "$(exists "$good_repo" reset-ran)" = no
assert_exit 0 test "$(exists '' reset-ran)" = unknown
assert_exit 0 test "$(exists "$ROOT" AGENTS.md)" = unknown
assert_exit 0 test "$(merged "$good_repo")" = no
assert_exit 0 test "$(merged '')" = unknown
assert_exit 0 test "$(committed "$good_repo")" = no
assert_exit 0 test "$(committed '')" = unknown
git -C "$good_repo" commit -q --allow-empty -m 'chore: moved'
assert_exit 0 test "$(committed "$good_repo")" = yes
git -C "$good_repo" merge -q --no-edit feature
assert_exit 0 test "$(merged "$good_repo")" = yes

# --- record

# row <mode wanted> <mode seen> <tried> <decision> <decision expected> <effect expected> <effect seen>:
# sets row_out to the line, and row_failures and row_not_exercised and row_passed to the
# counts it added.
row() {
  mode_wanted=$1
  mode=$2
  tried=$3
  decision=$4
  failures=0
  not_exercised=0
  passed=0
  row_out=$(record 'a case' "$5" "$6" "$7")
  # The counts have to come from the shell that kept them, not the substitution's.
  record 'a case' "$5" "$6" "$7" >/dev/null
  row_failures=$failures
  row_not_exercised=$not_exercised
  row_passed=$passed
}
log="$(tmp_dir)/log"
: >"$log"

assert_row() { # <failures> <not exercised> <passed> <text in the line>
  assert_exit 0 test "$row_failures" -eq "$1"
  assert_exit 0 test "$row_not_exercised" -eq "$2"
  assert_exit 0 test "$row_passed" -eq "$3"
  assert_contains "$row_out" "$4"
}

row default default yes ask ask no no
assert_row 0 0 1 ' ok'
row default default yes none none yes yes
assert_row 0 0 1 ' ok'

# What it's told apart from a pass.
row default default no ask ask no no
assert_row 1 0 0 'never tried'
row default default yes ask ask no yes
assert_row 1 0 0 'PASSED WITHOUT A PERSON'
row default default yes deny deny no yes
assert_row 1 0 0 'the effect was yes'
row default default yes none ask no no
assert_row 1 0 0 "the hook's decision was none"

# No repo to look in fails, even where the effect expected is "no".
row default default yes ask ask no unknown
assert_row 1 0 0 'the effect was unknown'

# Auto mode falls back to Manual when it isn't available, which proves nothing about auto.
row auto default yes ask ask no no
assert_row 0 1 0 'NOT EXERCISED'
row auto auto yes ask ask no no
assert_row 0 0 1 ' ok'

# Not exercised still can't hide a reset that ran.
row auto default yes ask ask no yes
assert_row 1 0 0 'PASSED WITHOUT A PERSON'

# Any other mode is asked for by a flag that always works, so a difference is a failure.
row dontAsk default yes ask ask no no
assert_row 1 0 0 'the mode was default, not dontAsk'
row default auto yes ask ask no no
assert_row 1 0 0 'the mode was auto, not default'
row dontAsk '' no ask ask no no
assert_row 1 0 0 'never tried'

# --- The committed test has no bypass case, and it reads through these helpers

live="$ROOT/tests/verify_only/live-hooks.test.sh"
assert_exit 1 grep -q 'bypassPermissions' "$live"
assert_exit 0 grep -q 'tests/lib/live.sh' "$live"

# --- The live test's own budget stays under a dollar

assert_exit 0 awk -v total="$budget_total" 'BEGIN { exit !(total < 1) }'
