#!/bin/sh
# Tests the rule on Write and Edit of workflows, through the real hook in a real repo. The
# shapes the trigger detector reads are tested with the detector, so these rows are about
# what's compared with what. At the end the pre-commit hook gets the same files, as the two
# have to agree.

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
# shellcheck source=tests/lib/assert.sh
. "$ROOT/tests/lib/assert.sh"
# shellcheck source=tests/lib/hook.sh
. "$ROOT/tests/lib/hook.sh"

plugin="$ROOT/plugins/dev-workflow"
hook="$plugin/scripts/hook-workflow-edit.sh"
templates="$plugin/skills/setup/templates/githooks"

GIT_CONFIG_GLOBAL=/dev/null
GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL GIT_CONFIG_NOSYSTEM

unset HOOK_PATH

repo="$(tmp_dir)/a b/repo"
new_repo "$repo"
mkdir -p "$repo/.claude" "$repo/.github/workflows" "$repo/sub"
cat >"$repo/.claude/dev-workflow.json" <<'JSON'
{ "ciAllowlist": [".github/workflows/release.yml", ".github/workflows/other.yaml"] }
JSON
CLAUDE_PROJECT_DIR=$repo
export CLAUDE_PROJECT_DIR
cd "$repo" || exit 1

workflow=.github/workflows/x.yml
allowed=.github/workflows/release.yml

on_disk() { # <content>, in the workflow
  printf '%s\n' "$1" >"$repo/$workflow"
}

no_file() {
  rm -f "$repo/$workflow"
}

write_input() { # <path> <content>
  jq -n --arg path "$1" --arg content "$2" --arg cwd "$PWD" \
    '{tool_name: "Write", tool_input: {file_path: $path, content: $content}, cwd: $cwd}'
}

edit_input() { # <path> <old> <new> [replace_all]
  jq -n --arg path "$1" --arg old "$2" --arg new "$3" --argjson all "${4:-false}" --arg cwd "$PWD" \
    '{tool_name: "Edit", tool_input: {file_path: $path, old_string: $old, new_string: $new, replace_all: $all}, cwd: $cwd}'
}

asks() { # <input> [text the reason must hold]...
  _asks_input=$1
  shift
  assert_decision ask "$hook" "$_asks_input"
  _asks_reason=$(reason_of "$hook" "$_asks_input")
  for _asks_text in "$@"; do
    assert_contains "$_asks_reason" "$_asks_text"
  done
}

passes() { # <input>
  assert_decision none "$hook" "$1"
}

# --- Write of a new file

no_file
asks "$(write_input "$workflow" 'on: pull_request')" 'pull_request' "$workflow" 'ciAllowlist'
asks "$(write_input "$workflow" 'on: pull_request_target')" 'pull_request_target'
asks "$(write_input "$workflow" 'on: push')" 'push'
asks "$(write_input "$workflow" 'on: [push, pull_request]')" 'push' 'pull_request'
asks "$(write_input .github/workflows/x.yaml 'on: push')" 'push'
asks "$(write_input "$repo/$workflow" 'on: push')" 'push'
passes "$(write_input "$workflow" 'on: workflow_dispatch')"
passes "$(write_input "$workflow" 'on: [workflow_dispatch, schedule]')"
passes "$(write_input .github/workflows/x.yaml 'on: workflow_dispatch')"

# Text that only mentions a trigger.
passes "$(write_input "$workflow" 'name: x
on: workflow_dispatch
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: push
        run: git push')"

# A shape the detector can't read could be hiding anything.
asks "$(write_input "$workflow" 'on: *x')" 'read the triggers' "$workflow"
asks "$(write_input "$workflow" '{on: push}')" 'read the triggers'

# --- What's a workflow, and whose

for elsewhere in \
  src/x.yml \
  x.yml \
  .github/x.yml \
  docs/.github/workflows/x.yml \
  .github/workflows/sub/x.yml \
  .github/workflows/x.txt \
  .github/workflows/x.yml.bak \
  .github/workflows \
  /elsewhere/.github/workflows/x.yml; do
  passes "$(write_input "$elsewhere" 'on: push')"
done
passes "$(edit_input src/x.yml 'a' 'on: push')"

# A relative path is from the session's folder, written however it's written.
for same_path in \
  ./.github/workflows/x.yml \
  .github//workflows/x.yml \
  .github/workflows/./x.yml \
  .github/workflows/../workflows/x.yml \
  sub/../.github/workflows/x.yml \
  no-such-folder/../.github/workflows/x.yml; do
  asks "$(write_input "$same_path" 'on: push')"
done
cd "$repo/sub" || exit 1
asks "$(write_input ../.github/workflows/x.yml 'on: push')"
passes "$(write_input .github/workflows/x.yml 'on: push')"
passes "$(write_input ../.github/workflows/release.yml 'on: push')"
cd "$repo" || exit 1

# Without a usable cwd, from the project's folder.
no_cwd=$(jq -n --arg path "$workflow" '{tool_name: "Write", tool_input: {file_path: $path, content: "on: push"}}')
asks "$no_cwd"
relative_cwd=$(jq -n --arg path "$workflow" '{tool_name: "Write", tool_input: {file_path: $path, content: "on: push"}, cwd: "sub"}')
asks "$relative_cwd"
gone_cwd=$(jq -n --arg path "$workflow" '{tool_name: "Write", tool_input: {file_path: $path, content: "on: push"}, cwd: "/no/such/folder"}')
asks "$gone_cwd"

# A link to the repo or into the folder is the same file.
links=$(tmp_dir)
ln -s "$repo" "$links/repo link"
ln -s "$repo/.github/workflows" "$repo/sub/workflows"
asks "$(write_input "$links/repo link/$workflow" 'on: push')"
passes "$(write_input "$links/repo link/$allowed" 'on: push')"
asks "$(write_input sub/workflows/x.yml 'on: push')"
rm "$repo/sub/workflows"

# A session can write into a worktree of this repo, which has its own project file.
git -C "$repo" add .claude
git -C "$repo" commit -q --no-verify -m 'chore: start'
worktree="$(tmp_dir)/a worktree"
git -C "$repo" worktree add -q -b feat/1-x "$worktree"
asks "$(write_input "$worktree/$workflow" 'on: push')"
passes "$(write_input "$worktree/$allowed" 'on: push')"
printf '{ "ciAllowlist": [".github/workflows/x.yml"] }\n' >"$worktree/.claude/dev-workflow.json"
passes "$(write_input "$worktree/$workflow" 'on: push')"
asks "$(write_input "$worktree/$allowed" 'on: push')"

# A repo that isn't a project is none of this hook's business.
outside="$(tmp_dir)/outside"
new_repo "$outside"
passes "$(write_input "$outside/$workflow" 'on: push')"

# --- The allowlist takes exact paths, and doesn't read the file at all

passes "$(write_input "$allowed" 'on: push')"
passes "$(write_input "$allowed" 'on: *x')"
passes "$(write_input .github/workflows/other.yaml 'on: push')"
passes "$(edit_input "$allowed" 'not there' 'on: push')"
for near in .github/workflows/lease.yml .github/workflows/release.yml.yml .github/workflows/other.yml; do
  asks "$(write_input "$near" 'on: push')"
done

# --- Write over a file: only what it gains counts

on_disk 'on: push'
passes "$(write_input "$workflow" 'name: edited
on: push')"
passes "$(write_input "$workflow" 'on: [push]')"
passes "$(write_input "$workflow" 'on: { push: {} }')"
passes "$(write_input "$workflow" 'on: workflow_dispatch')"
reason=$(reason_of "$hook" "$(write_input "$workflow" 'on: [push, pull_request]')")
assert_contains "$reason" 'pull_request'
assert_not_contains "$reason" 'push'
on_disk 'on: [pull_request_target]'
asks "$(write_input "$workflow" 'on: pull_request')" 'pull_request'

# A file that isn't readable as it stands vouches for nothing, and the new text decides.
on_disk 'on: *x'
asks "$(write_input "$workflow" 'on: push')" 'push'
passes "$(write_input "$workflow" 'on: workflow_dispatch')"
asks "$(write_input "$workflow" 'on: *y')" 'read the triggers'

# --- Edit: the file as the edit would leave it

on_disk 'on: workflow_dispatch'
asks "$(edit_input "$workflow" 'workflow_dispatch' 'push')" 'push'
asks "$(edit_input "$repo/$workflow" 'workflow_dispatch' 'push')" 'push'
passes "$(edit_input "$workflow" 'workflow_dispatch' 'schedule')"

# Adding push: under on:.
on_disk 'on:
  workflow_dispatch:
jobs:
  build: {}'
asks "$(edit_input "$workflow" '  workflow_dispatch:' '  workflow_dispatch:
  push:')" 'push'

# new_string alone says nothing about where it lands: here it looks like a trigger and
# isn't one.
on_disk 'on: workflow_dispatch
jobs:
  build:
    steps:
      - with:
          a: b'
passes "$(edit_input "$workflow" 'a: b' 'push: true')"
passes "$(edit_input "$workflow" 'a: b' 'on: push')"

# And here it doesn't, and the edit gives one. Removing text can do that.
on_disk 'on:
  # push:
  workflow_dispatch:'
asks "$(edit_input "$workflow" '# push:' 'push:')" 'push'
asks "$(edit_input "$workflow" '# ' '')" 'push'

# A trigger the file already has passes, even in new_string.
on_disk 'name: a
on: push'
passes "$(edit_input "$workflow" 'name: a' 'name: b')"
passes "$(edit_input "$workflow" 'on: push' 'on: [push]')"
passes "$(edit_input "$workflow" 'on: push' 'on: workflow_dispatch')"
reason=$(reason_of "$hook" "$(edit_input "$workflow" 'on: push' 'on: [push, pull_request]')")
assert_contains "$reason" 'pull_request'
assert_not_contains "$reason" 'has a push'

# Into a shape it can't read.
on_disk 'on: workflow_dispatch'
asks "$(edit_input "$workflow" 'workflow_dispatch' '*x')" 'read the triggers'

# replace_all: without it, only the first place changes.
on_disk '# workflow_dispatch
on: workflow_dispatch'
passes "$(edit_input "$workflow" 'workflow_dispatch' 'push')"
passes "$(edit_input "$workflow" 'workflow_dispatch' 'push' false)"
asks "$(edit_input "$workflow" 'workflow_dispatch' 'push' true)" 'push'
on_disk 'on: workflow_dispatch
# workflow_dispatch'
asks "$(edit_input "$workflow" 'workflow_dispatch' 'push')" 'push'

# The old text is plain text, whatever's in it, and so is the new.
on_disk 'on: [workflow_dispatch]'
asks "$(edit_input "$workflow" '[workflow_dispatch]' '[push]')" 'push'
asks "$(edit_input "$workflow" '[.*]' '[push]')" 'what this does'
on_disk 'on: workflow_dispatch # a.c'
passes "$(edit_input "$workflow" 'a.c' 'push')"

# Windows line endings stay what they are.
printf 'name: x\r\non: workflow_dispatch\r\n' >"$repo/$workflow"
asks "$(edit_input "$workflow" 'workflow_dispatch' 'push')" 'push'

# Bytes that aren't text don't get in the way.
printf '# \377\376\non: workflow_dispatch\n' >"$repo/$workflow"
asks "$(edit_input "$workflow" 'workflow_dispatch' 'push')" 'push'
passes "$(edit_input "$workflow" 'workflow_dispatch' 'schedule')"

# Creating a file by Edit: an empty old_string, on no file or an empty one.
no_file
asks "$(edit_input "$workflow" '' 'on: push')" 'push'
passes "$(edit_input "$workflow" '' 'on: workflow_dispatch')"
: >"$repo/$workflow"
asks "$(edit_input "$workflow" '' 'on: push')" 'push'
passes "$(edit_input "$workflow" '' 'on: workflow_dispatch')"

# An edit that can't apply can't be followed: the tool will probably refuse it, and a
# question about it costs less than a guess.
on_disk 'on: workflow_dispatch'
cant_tell="what this does"
asks "$(edit_input "$workflow" 'not there' 'on: push')" "$cant_tell" "$workflow"
asks "$(edit_input "$workflow" '' 'on: push')" "$cant_tell"
no_file
asks "$(edit_input "$workflow" 'not there' 'on: push')" "$cant_tell"

# A file that's there but can't be read.
mkdir -p "$repo/$workflow"
asks "$(write_input "$workflow" 'on: workflow_dispatch')" "$cant_tell"
asks "$(edit_input "$workflow" '' 'on: workflow_dispatch')" "$cant_tell"
rmdir "$repo/$workflow"
ln -s no-such-file "$repo/$workflow"
asks "$(write_input "$workflow" 'on: workflow_dispatch')" "$cant_tell"
rm "$repo/$workflow"
on_disk 'on: workflow_dispatch'
chmod 000 "$repo/$workflow"
if [ ! -r "$repo/$workflow" ]; then
  asks "$(write_input "$workflow" 'on: workflow_dispatch')" "$cant_tell"
fi
chmod 644 "$repo/$workflow"

# A link to a real file reads that file.
printf 'on: push\n' >"$repo/real.yml"
no_file
ln -s ../../real.yml "$repo/$workflow"
passes "$(write_input "$workflow" 'name: x
on: push')"
asks "$(write_input "$workflow" 'on: [push, pull_request]')" 'pull_request'
rm "$repo/$workflow"

# --- Calls that aren't what they should be

no_file
tool_call() { # <tool> <tool_input as JSON>
  jq -n --arg tool "$1" --argjson input "$2" --arg cwd "$PWD" '{tool_name: $tool, tool_input: $input, cwd: $cwd}'
}
asks "$(tool_call Write '{"file_path": ".github/workflows/x.yml"}')" "$cant_tell"
asks "$(tool_call Write '{"file_path": ".github/workflows/x.yml", "content": 1}')" "$cant_tell"
asks "$(tool_call Edit '{"file_path": ".github/workflows/x.yml", "new_string": "on: push"}')" "$cant_tell"
asks "$(tool_call Edit '{"file_path": ".github/workflows/x.yml", "old_string": ""}')" "$cant_tell"
# With no path, or from a tool this isn't for, there's nothing to say.
passes "$(tool_call Write '{"content": "on: push"}')"
passes "$(tool_call Write '{"file_path": 1, "content": "on: push"}')"
passes "$(tool_call Read '{"file_path": ".github/workflows/x.yml", "content": "on: push"}')"
passes "$(tool_call MultiEdit '{"file_path": ".github/workflows/x.yml"}')"
assert_decision deny "$hook" 'not json'
assert_decision deny "$hook" '{"tool_name": "Write", "tool_input": "not an object"}'

# --- A broken allowlist can't vouch for anything, but only workflows need it

broken="$(tmp_dir)/broken"
new_repo "$broken"
mkdir -p "$broken/.claude"
CLAUDE_PROJECT_DIR=$broken
cd "$broken" || exit 1
for contents in '{"ciAllowlist": ".github/workflows/x.yml"}' '{"ciAllowlist": {"a": 1}}'; do
  printf '%s\n' "$contents" >"$broken/.claude/dev-workflow.json"
  assert_decision deny "$hook" "$(write_input "$workflow" 'on: workflow_dispatch')"
  assert_contains "$(reason_of "$hook" "$(write_input "$workflow" 'on: workflow_dispatch')")" 'ciAllowlist'
  passes "$(write_input src/x.yml 'on: push')"
done
# No list is an empty one, and a word in it that isn't a path is no path.
printf '{}\n' >"$broken/.claude/dev-workflow.json"
asks "$(write_input "$workflow" 'on: push')"
printf '{"ciAllowlist": [1, ".github/workflows/x.yml"]}\n' >"$broken/.claude/dev-workflow.json"
passes "$(write_input "$workflow" 'on: push')"
CLAUDE_PROJECT_DIR=$repo
cd "$repo" || exit 1

# --- Doing nothing outside a project

bare="$(tmp_dir)/bare"
mkdir "$bare"
no_tools=$(tmp_dir)
input=$(write_input "$repo/$workflow" 'on: push')
CLAUDE_PROJECT_DIR=$bare
passes "$input"
# Without jq too, and nothing outside the shell runs before the gate.
HOOK_PATH=$no_tools
assert_decision none "$hook" "$input"
CLAUDE_PROJECT_DIR=$repo
# In a project, no jq blocks.
assert_decision deny "$hook" "$input"
assert_contains "$(reason_of "$hook" "$input")" 'jq'
unset HOOK_PATH

# --- The hook runs from another folder and by a relative path

assert_exit 0 test -x "$hook"
assert_contains "$(cd "$plugin/scripts" && printf '%s' "$input" | sh hook-workflow-edit.sh)" '"ask"'
assert_contains "$(cd "$plugin" && printf '%s' "$input" | sh scripts/hook-workflow-edit.sh)" '"ask"'

# --- What the hook relies on, failing or missing, doesn't pass a file

fake_tools=$(tmp_dir)
for tool in jq cat; do
  ln -s "$(command -v "$tool")" "$fake_tools/$tool"
done
cat >"$fake_tools/awk" <<'FAKE'
#!/bin/sh
exit 2
FAKE
chmod +x "$fake_tools/awk"
clean_input=$(write_input "$workflow" 'on: workflow_dispatch')
passes "$clean_input"
HOOK_PATH=$fake_tools
asks "$clean_input" 'read the triggers'
unset HOOK_PATH

# A heredoc the shell can't create leaves the hook's loop unrun, which gains no trigger.
new_trigger=$(write_input "$workflow" 'on: pull_request')
no_temp="$(tmp_dir)/no-temp"
mkdir "$no_temp"
chmod 555 "$no_temp"
real_tmpdir=${TMPDIR:-}
TMPDIR=$no_temp
export TMPDIR
output=$(printf '%s' "$new_trigger" | sh "$hook" 2>/dev/null)
TMPDIR=$real_tmpdir
assert_contains "$output" '"permissionDecision":"'
chmod 755 "$no_temp"
without_temp=$(hook_without_temp_files "$hook")
if [ -n "$without_temp" ]; then
  assert_decision deny "$without_temp" "$new_trigger"
  assert_contains "$(reason_of "$without_temp" "$new_trigger")" "can't be checked"
fi

partial="$(tmp_dir)/partial"
mkdir -p "$partial/scripts/lib"
cp "$hook" "$partial/scripts/"
cp "$plugin/scripts/lib/"* "$partial/scripts/lib/"
assert_decision deny "$partial/scripts/hook-workflow-edit.sh" "$clean_input"
assert_contains "$(reason_of "$partial/scripts/hook-workflow-edit.sh" "$clean_input")" 'dw-lib.sh'
# A file that isn't a workflow doesn't need it.
assert_decision none "$partial/scripts/hook-workflow-edit.sh" "$(write_input src/x.yml 'on: push')"

# --- The same answer as pre-commit, on a new file and on one with a trigger

parity="$(tmp_dir)/parity"
new_repo "$parity"
git -C "$parity" config core.hooksPath .githooks
mkdir -p "$parity/.githooks" "$parity/.claude" "$parity/.github/workflows"
cp "$templates/pre-commit" "$templates/dw-lib.sh" "$parity/.githooks/"
cat >"$parity/.githooks/dev-workflow.env" <<'ENV'
DW_DEFAULT_BRANCH='main'
DW_CHECK='scripts/check'
DW_CI_ALLOWLIST='.github/workflows/release.yml'
DW_FORMATTERS=''
ENV
printf '{"ciAllowlist": [".github/workflows/release.yml"]}\n' >"$parity/.claude/dev-workflow.json"
printf '.githooks\n.claude\n' >>"$parity/.git/info/exclude"
git -C "$parity" commit -q --allow-empty -m 'feat: start'
base=$(git -C "$parity" rev-parse HEAD)
CLAUDE_PROJECT_DIR=$parity
cd "$parity" || exit 1

same_answer() { # <path> <content>
  _same_decision=$(decision_of "$hook" "$(write_input "$1" "$2")") ||
    _assert_fail "no readable decision for: $2"
  mkdir -p "$(dirname "$1")"
  printf '%s\n' "$2" >"$1"
  git add -- "$1"
  if git commit -q -m 'feat: x' >/dev/null 2>&1; then
    _same_commit=none
  else
    _same_commit=ask
  fi
  [ "$_same_decision" = "$_same_commit" ] ||
    _assert_fail "the hook said $_same_decision and the commit gave $_same_commit for $1: $2"
  git reset -q --hard "$base" || _assert_fail "could not reset the fixture"
  git clean -fdq || _assert_fail "could not clean the fixture"
}

for content in \
  'on: push' \
  'on: [pull_request]' \
  'on:
  pull_request_target:' \
  'on: workflow_dispatch' \
  'name: push
on: workflow_dispatch' \
  'on: *x' \
  '{on: push}'; do
  same_answer "$workflow" "$content"
  same_answer .github/workflows/x.yaml "$content"
  same_answer "$allowed" "$content"
  same_answer .github/workflows/sub/x.yml "$content"
  same_answer src/x.yml "$content"
done

mkdir -p "$(dirname "$workflow")"
printf 'on: push\n' >"$workflow"
git add -- "$workflow"
git commit -q --no-verify -m 'feat: a trigger'
base=$(git rev-parse HEAD)
for content in \
  'name: edited
on: push' \
  'on: [push, pull_request]' \
  'on: workflow_dispatch' \
  'on: *x'; do
  same_answer "$workflow" "$content"
done
