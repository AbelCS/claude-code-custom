#!/bin/sh
# shellcheck disable=SC2016 # Dollars and backticks in quotes are for the hook scripts.
#
# Tests the library the Claude Code hooks share: the gate that decides whether a hook
# acts at all, the decisions it prints, and reading the project file.

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
# shellcheck source=tests/lib/assert.sh
. "$ROOT/tests/lib/assert.sh"
# shellcheck source=tests/lib/hook.sh
. "$ROOT/tests/lib/hook.sh"

common="$ROOT/plugins/dev-workflow/scripts/lib/common.sh"

# Claude Code exports this, and it would point the tests at the real repo.
unset CLAUDE_PROJECT_DIR HOOK_PATH

scratch=$(tmp_dir)
script="$scratch/hook.sh"

# An empty PATH: whatever runs under it uses nothing but the shell's builtins.
no_tools="$scratch/no-tools"
mkdir "$no_tools"

# write_hook <body>: the script a hook would be, sourcing the library. Each call
# replaces the last.
write_hook() {
  printf '. "%s"\n%s\n' "$common" "$1" >"$script"
}

# new_project <dir> [contents]: a project with a project file.
new_project() {
  mkdir -p "$1/.claude"
  printf '%s\n' "${2:-"{\"commands\":{\"check\":\"scripts/check\"}}"}" >"$1/.claude/dev-workflow.json"
}

project_dir() {
  CLAUDE_PROJECT_DIR=$1
  export CLAUDE_PROJECT_DIR
}

no_project_dir() {
  unset CLAUDE_PROJECT_DIR
}

# Getting through the gate shows as "ask" with the project it found, so it can't be
# confused with the gate stopping quietly ("none") or blocking ("deny").
write_hook 'dw_gate
dw_ask "through the gate to $DW_PROJECT_DIR"'
gate=$script

# A path with a space, because a project can live in one.
repo="$(tmp_dir)/a b/repo"
new_project "$repo"
bare="$(tmp_dir)/a b/bare"
mkdir -p "$bare"

input=$(bash_input 'npm test')

# input_from <cwd>: hook input from that directory.
input_from() {
  jq -n --arg cwd "$1" '{tool_name: "Bash", tool_input: {command: "npm test"}, cwd: $cwd}'
}

# --- The gate, with CLAUDE_PROJECT_DIR set

project_dir "$bare"
assert_decision none "$gate" "$input"

# No project file and no jq: nothing happens, and nothing outside the shell runs.
HOOK_PATH=$no_tools
assert_decision none "$gate" "$input"
unset HOOK_PATH

project_dir "$repo"
assert_decision ask "$gate" "$input"
assert_contains "$(reason_of "$gate" "$input")" "through the gate to $repo"

# Project file and no jq: blocked, with a reason written without jq.
HOOK_PATH=$no_tools
assert_decision deny "$gate" "$input"
assert_contains "$(reason_of "$gate" "$input")" 'jq'
unset HOOK_PATH

# Without a project file jq must not even start: a project may not have it.
fake_jq="$scratch/fake-jq"
mkdir "$fake_jq"
cat >"$fake_jq/jq" <<FAKE
#!/bin/sh
: >"$scratch/jq ran"
exit 1
FAKE
chmod +x "$fake_jq/jq"
project_dir "$bare"
HOOK_PATH=$fake_jq
assert_decision none "$gate" "$input"
unset HOOK_PATH
assert_exit 1 test -e "$scratch/jq ran"

# A project file that can't be used blocks, naming it.
broken="$(tmp_dir)/a b/broken"
project_dir "$broken"
blocks_naming_file() {
  assert_decision deny "$gate" "$input"
  assert_contains "$(reason_of "$gate" "$input")" "$broken/.claude/dev-workflow.json"
}
new_project "$broken" '{"commands":'
blocks_naming_file
: >"$broken/.claude/dev-workflow.json"
blocks_naming_file
new_project "$broken" '["not an object"]'
blocks_naming_file
new_project "$broken" '{} {}'
blocks_naming_file
rm "$broken/.claude/dev-workflow.json"
ln -s "$broken/nowhere" "$broken/.claude/dev-workflow.json"
blocks_naming_file
rm "$broken/.claude/dev-workflow.json"
mkdir "$broken/.claude/dev-workflow.json"
blocks_naming_file
rmdir "$broken/.claude/dev-workflow.json"

# A valid project file with hook input that can't be read: nothing could be checked.
project_dir "$repo"
assert_decision deny "$gate" 'not json'
assert_decision deny "$gate" ''
assert_decision deny "$gate" '[]'

# --- The gate, without CLAUDE_PROJECT_DIR: it falls back to the input's cwd

no_project_dir
assert_decision ask "$gate" "$(input_from "$repo")"
assert_contains "$(reason_of "$gate" "$(input_from "$repo")")" "through the gate to $repo"

# From a subfolder, a project is still a project.
mkdir -p "$repo/src/deep"
assert_decision ask "$gate" "$(input_from "$repo/src/deep")"
assert_contains "$(reason_of "$gate" "$(input_from "$repo/src/deep")")" "through the gate to $repo"

assert_decision none "$gate" "$(input_from "$bare")"

# Nothing says where the project is.
assert_decision none "$gate" 'not json'
assert_decision none "$gate" '{"tool_name":"Bash"}'
assert_decision none "$gate" '{"cwd":3}'
assert_decision none "$gate" '{"cwd":"relative/path"}'

# Reading cwd takes jq, so without jq there's no project to find.
HOOK_PATH=$no_tools
assert_decision none "$gate" "$(input_from "$repo")"
unset HOOK_PATH

new_project "$broken" 'not json'
assert_decision deny "$gate" "$(input_from "$broken")"
assert_contains "$(reason_of "$gate" "$(input_from "$broken")")" "$broken/.claude/dev-workflow.json"

# An empty variable says nothing either.
project_dir ''
assert_decision ask "$gate" "$(input_from "$repo")"

# The variable wins over the input.
project_dir "$bare"
assert_decision none "$gate" "$(input_from "$repo")"

# --- Finding the project from a subfolder: up to the first .git

# assert_found_at <dir> <json>: exactly that directory, not one above or below it.
assert_found_at() {
  assert_decision ask "$gate" "$2"
  found=$(reason_of "$gate" "$2")
  [ "$found" = "through the gate to $1" ] || _assert_fail "expected the project at $1, got: $found"
}

tree="$(tmp_dir)/a b/git repo"
new_project "$tree"
mkdir "$tree/.git"
mkdir -p "$tree/sub/deep"

project_dir "$tree"
assert_found_at "$tree" "$input"
project_dir "$tree/sub"
assert_found_at "$tree" "$input"
project_dir "$tree/sub/deep"
assert_found_at "$tree" "$input"
no_project_dir
assert_found_at "$tree" "$(input_from "$tree/sub/deep")"

# A subfolder of a project needs jq like the root does.
project_dir "$tree/sub"
HOOK_PATH=$no_tools
assert_decision deny "$gate" "$input"
assert_contains "$(reason_of "$gate" "$input")" 'jq'
unset HOOK_PATH

# A broken project file above blocks from a subfolder too.
broken_tree="$(tmp_dir)/a b/broken tree"
new_project "$broken_tree" 'not json'
mkdir -p "$broken_tree/sub"
project_dir "$broken_tree/sub"
assert_decision deny "$gate" "$input"
assert_contains "$(reason_of "$gate" "$input")" "$broken_tree/.claude/dev-workflow.json"

# stops_at_git <dir below or at the nested repo>: it doesn't take its parent's file,
# from the variable or from cwd, and needs no tool to decide that.
stops_at_git() {
  project_dir "$1"
  assert_decision none "$gate" "$input"
  HOOK_PATH=$no_tools
  assert_decision none "$gate" "$input"
  HOOK_PATH=$fake_jq
  assert_decision none "$gate" "$input"
  unset HOOK_PATH
  assert_exit 1 test -e "$scratch/jq ran"
  no_project_dir
  assert_decision none "$gate" "$(input_from "$1")"
}

# A nested repo, with a .git folder.
nested="$tree/vendor/other"
mkdir -p "$nested/.git" "$nested/src"
stops_at_git "$nested"
stops_at_git "$nested/src"

# A worktree or submodule, where .git is a file.
worktree="$tree/vendor/worktree"
mkdir -p "$worktree/src"
printf 'gitdir: /somewhere/else\n' >"$worktree/.git"
stops_at_git "$worktree"
stops_at_git "$worktree/src"

# A .git that's a dangling link still marks a repo.
linked="$tree/vendor/linked"
mkdir -p "$linked/src"
ln -s "$linked/nowhere" "$linked/.git"
stops_at_git "$linked/src"

# A nested repo with its own project file is its own project.
own="$tree/vendor/own"
mkdir -p "$own/.git" "$own/src"
new_project "$own"
project_dir "$own/src"
assert_found_at "$own" "$input"

# A .git between the start and the project file stops the walk, so a folder above the
# repo holding a project file doesn't count.
inner="$(tmp_dir)/a b/outer"
new_project "$inner"
mkdir -p "$inner/repo/.git"
stops_at_git "$inner/repo"

# With no .git at all the walk ends at the filesystem root, with no decision.
project_dir "$bare/sub/deep"
assert_decision none "$gate" "$input"
HOOK_PATH=$no_tools
assert_decision none "$gate" "$input"
unset HOOK_PATH
no_project_dir
assert_decision none "$gate" "$(input_from "$bare/sub/deep")"
assert_decision none "$gate" "$(input_from "/")"

# A relative variable can't be walked past its start, and must still end.
project_dir 'relative/path'
assert_decision none "$gate" "$input"
project_dir 'relative'
assert_decision none "$gate" "$input"

# --- Reading the hook input and the project file after the gate

write_hook 'dw_gate
dw_ask "$(dw_input .tool_input.command)|$(dw_project .commands.check)|$(dw_project ".missing // empty")"'
project_dir "$repo"
assert_contains "$(reason_of "$script" "$input")" 'npm test|scripts/check|'
no_project_dir
assert_contains "$(reason_of "$script" "$(input_from "$repo/src")")" 'npm test|scripts/check|'

# A filter that fails is the caller's to see, even from inside a substitution.
write_hook 'dw_gate
if value=$(dw_project ".commands | error" 2>/dev/null); then dw_ask "no failure: $value"; fi
if value=$(dw_input ".tool_input | error" 2>/dev/null); then dw_ask "no failure: $value"; fi'
project_dir "$repo"
assert_decision none "$script" "$input"

# --- The decisions

for decision in deny ask; do
  write_hook "dw_$decision 'plain reason'
echo 'still running'"
  actual=$(env PATH="$no_tools" "$(command -v sh)" "$script" </dev/null)
  expected='{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"'"$decision"'","permissionDecisionReason":"plain reason"}}'
  [ "$actual" = "$expected" ] || _assert_fail "expected $expected, got $actual"
done

# Whatever a reason holds comes through whole, without jq. It's handed over in the
# environment so that the script can't change it.
reason_comes_through() {
  DW_TEST_REASON=$1
  export DW_TEST_REASON
  for decision in deny ask; do
    write_hook "dw_$decision \"\$DW_TEST_REASON\""
    HOOK_PATH=$no_tools
    assert_decision "$decision" "$script" ''
    actual=$(reason_of "$script" '')
    unset HOOK_PATH
    [ "$actual" = "$1" ] || _assert_fail "expected reason [$1], got [$actual]"
  done
}
reason_comes_through 'say "hi" to "them"'
# shellcheck disable=SC1003 # The backslash is the point.
reason_comes_through 'C:\temp\new and a trailing backslash\'
reason_comes_through '\\ and \" and \n stay as typed'
reason_comes_through 'first
second

fourth'
reason_comes_through "$(printf 'tab\there, return\rhere, bell\007here, escape\033here')"
reason_comes_through '$(not run) `not run` $HOME %s %d * ? [a] '"'"'quoted'"'"
reason_comes_through "$(printf 'caf\303\251 \342\200\224 \360\237\244\226 end')"
reason_comes_through ''

# Ending in newlines, which a command substitution would lose, so read from the JSON.
write_hook 'dw_deny "ends in one
"'
assert_contains "$(sh "$script" </dev/null)" 'ends in one\n"'

# --- The test helpers: output Claude Code can't read as a decision fails the test

good='{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"r"}}'
write_hook 'printf "%s\n" "$DW_TEST_OUTPUT"'

not_a_decision() {
  DW_TEST_OUTPUT=$1
  export DW_TEST_OUTPUT
  assert_exit 1 decision_of "$script" ''
  assert_exit 1 reason_of "$script" ''
  assert_exit 1 assert_decision deny "$script" ''
  assert_exit 1 assert_decision none "$script" ''
  printed=$(decision_of "$script" '' 2>/dev/null)
  [ -z "$printed" ] || _assert_fail "decision_of printed [$printed] for: $1"
  printed=$(reason_of "$script" '' 2>/dev/null)
  [ -z "$printed" ] || _assert_fail "reason_of printed [$printed] for: $1"
}
not_a_decision "$good
still running"
not_a_decision "still running
$good"
not_a_decision "$good
$good"
not_a_decision 'plain text'
not_a_decision '{}'
not_a_decision '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"r"}}'
not_a_decision '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny"}}'
not_a_decision '{"hookSpecificOutput":{"hookEventName":"PostToolUse","permissionDecision":"deny","permissionDecisionReason":"r"}}'

# The same helpers still pass what's right.
DW_TEST_OUTPUT=$good
assert_decision deny "$script" ''
[ "$(reason_of "$script" '')" = 'r' ] || _assert_fail 'reason_of lost a good reason'

# A hook that fails fails the test too, whatever it printed first.
write_hook "printf '%s\\n' '$good'
exit 3"
assert_exit 1 decision_of "$script" ''
assert_exit 1 assert_decision deny "$script" ''
