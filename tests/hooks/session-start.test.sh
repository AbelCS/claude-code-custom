#!/bin/sh
# Tests the session-start check through the real script, in real repos: silent when all
# is well, one line for each thing wrong, and never a failure.

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
# shellcheck source=tests/lib/assert.sh
. "$ROOT/tests/lib/assert.sh"

plugin="$ROOT/plugins/dev-workflow"
hook="$plugin/scripts/hook-session-start.sh"
shell_path=$(command -v sh)

# What the session's environment could bring in from the machine running the tests.
unset CLAUDE_CONFIG_DIR CLAUDE_PLUGIN_OPTION_MAINTENANCE_INTERVAL_DAYS

# bin_with <tool...>: a folder holding only these tools.
bin_with() {
  bw_dir=$(tmp_dir)
  for bw_tool in "$@"; do
    ln -s "$(command -v "$bw_tool")" "$bw_dir/$bw_tool" ||
      _assert_fail "could not link $bw_tool"
  done
  printf '%s\n' "$bw_dir"
}

# add_script <bin> <name> <body>
add_script() {
  printf '#!%s\n%s\n' "$shell_path" "$3" >"$1/$2"
  chmod +x "$1/$2"
}

# Today is fixed, and gh must only be looked for: asking it anything is slow.
gh_log="$(tmp_dir)/gh-was-run"
bin=$(bin_with git jq grep)
add_script "$bin" date 'echo 2026-06-15'
add_script "$bin" gh "echo run >>'$gh_log'"

# write_registry <home> <plugin id...>: a user-scope install of each.
write_registry() {
  wr_home=$1
  shift
  mkdir -p "$wr_home/.claude/plugins"
  jq -n '{version: 2, plugins: ($ARGS.positional | map({key: ., value: [{scope: "user", version: "1.0.0"}]}) | from_entries)}' \
    --args "$@" >"$wr_home/.claude/plugins/installed_plugins.json"
}

every_plugin='superpowers@claude-plugins-official context7@claude-plugins-official serena@claude-plugins-official intent@intent ui-ux-pro-max@ui-ux-pro-max-skill'
home=$(tmp_dir)
# shellcheck disable=SC2086 # A list of words.
write_registry "$home" $every_plugin

# new_project [project file text]: prints a set-up repo where nothing is wrong.
all_well='{"pluginVersion": "99.0.0", "hasScreens": true}'
new_project() {
  np_dir="$(tmp_dir)/a b/repo"
  new_repo "$np_dir"
  mkdir -p "$np_dir/.claude" "$np_dir/docs"
  printf '%s\n' "${1:-$all_well}" >"$np_dir/.claude/dev-workflow.json"
  # shellcheck disable=SC2016 # The real file's backticks.
  printf '# Maintenance\n\nOne line per run, in the form `YYYY-MM-DD: what was done`.\n' >"$np_dir/docs/maintenance.md"
  git -C "$np_dir" config core.hooksPath .githooks
  printf '%s\n' "$np_dir"
}

# start <folder> [hook script]: runs the check from that folder as Claude Code does, with
# <folder> as the project unless project_dir says otherwise. Sets out. It must exit 0 and
# leave stderr empty. Takes its environment from bin, home and project_dir.
errors="$(tmp_dir)/errors"
project_dir=
start() {
  if ! out=$(cd "$1" && HOME=$home PATH=$bin CLAUDE_PROJECT_DIR=${project_dir:-$1} "$shell_path" "${2:-$hook}" </dev/null 2>"$errors"); then
    _assert_fail "the check failed in $1: $out $(cat "$errors")"
  fi
  [ ! -s "$errors" ] || _assert_fail "the check wrote to stderr in $1: $(cat "$errors")"
}

assert_silent() {
  [ -z "$out" ] || _assert_fail "expected no output, got: $out"
}

# assert_one_line <text>...: exactly one line, starting with the plugin's name and holding
# each text.
assert_one_line() {
  [ -n "$out" ] || _assert_fail "expected one line, got nothing"
  [ "$(printf '%s\n' "$out" | wc -l)" -eq 1 ] || _assert_fail "expected one line, got: $out"
  assert_contains "$out" 'dev-workflow: '
  for aol_text in "$@"; do
    assert_contains "$out" "$aol_text"
  done
}

# set_last_run <repo> <text of the last line>
set_last_run() {
  printf '%s\n' "- 2020-01-01: an earlier run" "$2" >>"$1/docs/maintenance.md"
}

# --- All well

repo=$(new_project)
start "$repo"
assert_silent

# A log with runs that aren't overdue, from a subfolder of the project.
set_last_run "$repo" '- 2026-06-14: updated the dependencies'
mkdir "$repo/sub"
project_dir=$repo
start "$repo/sub"
assert_silent
project_dir=

# --- No project file: nothing, and nothing outside the shell, jq included

plain="$(tmp_dir)/plain repo"
new_repo "$plain"
saved_bin=$bin
bin=$(tmp_dir)
start "$plain"
assert_silent

# Not a repo, a folder that's gone, and no project variable at all.
not_a_repo=$(tmp_dir)
start "$not_a_repo"
assert_silent
project_dir="$not_a_repo/gone"
start "$not_a_repo"
assert_silent
project_dir=
out=$(cd "$plain" && unset CLAUDE_PROJECT_DIR && HOME=$home PATH=$bin "$shell_path" "$hook" </dev/null 2>&1) ||
  _assert_fail "the check failed with no project variable: $out"
assert_silent

# A nested repo doesn't take its parent's project file.
outer=$(new_project)
new_repo "$outer/inner"
start "$outer/inner"
assert_silent
bin=$saved_bin

# Without the variable it goes by where it's run.
repo=$(new_project)
git -C "$repo" config --unset core.hooksPath
out=$(cd "$repo" && unset CLAUDE_PROJECT_DIR && HOME=$home PATH=$bin "$shell_path" "$hook" </dev/null) ||
  _assert_fail "the check failed with no project variable: $out"
assert_one_line 'git config core.hooksPath .githooks'

# --- Git hooks

repo=$(new_project)
git -C "$repo" config --unset core.hooksPath
start "$repo"
assert_one_line 'git config core.hooksPath .githooks'

# add_git_hook <repo> <hook> <text>: an executable hook in git's own folder.
add_git_hook() {
  mkdir -p "$1/.git/hooks"
  printf '#!/bin/sh\n%s\n' "$3" >"$1/.git/hooks/$2"
  chmod +x "$1/.git/hooks/$2"
}

# What each tool writes there, so that it counts without core.hooksPath.
# shellcheck disable=SC2016 # Text from other tools' scripts.
for tool_text in \
  'call_lefthook run "pre-commit" "$@"' \
  '# File generated by pre-commit: https://pre-commit.com' \
  'if [ "$SKIP_SIMPLE_GIT_HOOKS" = "1" ]; then exit 0; fi' \
  '# Entrypoint for Overcommit hook integration' \
  '. "$(dirname "$0")/husky.sh"'; do
  repo=$(new_project)
  git -C "$repo" config --unset core.hooksPath
  add_git_hook "$repo" pre-commit "$tool_text"
  start "$repo"
  assert_silent
done

# Git skips one that isn't executable, git's samples do nothing, and a hook somebody wrote
# for another purpose says nothing about these.
repo=$(new_project)
git -C "$repo" config --unset core.hooksPath
add_git_hook "$repo" pre-commit 'call_lefthook'
chmod -x "$repo/.git/hooks/pre-commit"
add_git_hook "$repo" pre-push.sample 'call_lefthook'
add_git_hook "$repo" pre-push 'echo my own hook'
start "$repo"
assert_one_line 'git config core.hooksPath .githooks'

# A project file ahead of git init has no hooks to turn on yet.
no_git=$(tmp_dir)
mkdir "$no_git/.claude"
printf '{"pluginVersion": "99.0.0"}\n' >"$no_git/.claude/dev-workflow.json"
start "$no_git"
assert_silent

# --- Git hooks in a worktree: that worktree's own config

repo=$(new_project)
git -C "$repo" config --unset core.hooksPath
git -C "$repo" add .claude docs
git -C "$repo" commit -q -m 'chore: first'
git -C "$repo" config extensions.worktreeConfig true
worktree="$(tmp_dir)/the worktree"
git -C "$repo" worktree add -q -b other "$worktree"

git -C "$worktree" config --worktree core.hooksPath .githooks
start "$worktree"
assert_silent
start "$repo"
assert_one_line 'git config core.hooksPath .githooks'

git -C "$worktree" config --worktree --unset core.hooksPath
git -C "$repo" config --worktree core.hooksPath .githooks
start "$repo"
assert_silent
start "$worktree"
assert_one_line 'git config core.hooksPath .githooks'

# A session in the worktree whose project variable names the main checkout.
project_dir=$repo
start "$worktree"
assert_one_line 'git config core.hooksPath .githooks'
project_dir=

# A known tool's hook is shared with the worktree, in the main repo's folder.
add_git_hook "$repo" pre-push 'call_lefthook'
start "$worktree"
assert_silent

# --- Stale pluginVersion

repo=$(new_project '{"pluginVersion": "0.0.1", "hasScreens": true}')
start "$repo"
assert_one_line '/dev-workflow:setup' '0.0.1' "$(jq -r .version "$plugin/.claude-plugin/plugin.json")"

repo=$(new_project '{"hasScreens": true}')
start "$repo"
assert_one_line '/dev-workflow:setup' 'pluginVersion'

repo=$(new_project '{"pluginVersion": "soon", "hasScreens": true}')
start "$repo"
assert_one_line '/dev-workflow:setup' 'soon'

# By number, part by part, against a copy of the plugin with its own version.
copy="$(tmp_dir)/the plugin"
mkdir -p "$copy/.claude-plugin"
cp -R "$plugin/scripts" "$copy/"
printf '{"name": "x", "version": "1.10.0"}\n' >"$copy/.claude-plugin/plugin.json"
for older in 1.9.0 1.9.99 0.99.99 1; do
  repo=$(new_project "{\"pluginVersion\": \"$older\", \"hasScreens\": true}")
  start "$repo" "$copy/scripts/hook-session-start.sh"
  assert_one_line "$older" '1.10.0'
done
for not_older in 1.10.0 1.10 1.10.1 1.11.0 2.0.0 1.10.0-rc.1; do
  repo=$(new_project "{\"pluginVersion\": \"$not_older\", \"hasScreens\": true}")
  start "$repo" "$copy/scripts/hook-session-start.sh"
  assert_silent
done

# A plugin with no version to compare, or no manifest, can't call anything stale.
printf '{"name": "x"}\n' >"$copy/.claude-plugin/plugin.json"
repo=$(new_project '{"pluginVersion": "0.0.1", "hasScreens": true}')
start "$repo" "$copy/scripts/hook-session-start.sh"
assert_silent
rm "$copy/.claude-plugin/plugin.json"
start "$repo" "$copy/scripts/hook-session-start.sh"
assert_silent

# --- Maintenance, with today fixed at 2026-06-15

# interval_case <interval or unset> <last run> <overdue|fine>: a run is overdue when it's
# more days old than the interval, and not on the day itself.
interval_case() {
  ic_repo=$(new_project)
  set_last_run "$ic_repo" "- $2: a run"
  if [ "$1" = unset ]; then
    unset CLAUDE_PLUGIN_OPTION_MAINTENANCE_INTERVAL_DAYS
  else
    CLAUDE_PLUGIN_OPTION_MAINTENANCE_INTERVAL_DAYS=$1
    export CLAUDE_PLUGIN_OPTION_MAINTENANCE_INTERVAL_DAYS
  fi
  start "$ic_repo"
  unset CLAUDE_PLUGIN_OPTION_MAINTENANCE_INTERVAL_DAYS
  if [ "$3" = overdue ]; then
    assert_one_line '/dev-workflow:maintain'
  else
    assert_silent
  fi
}

interval_case 10 2026-06-05 fine
interval_case 10 2026-06-04 overdue
interval_case 45 2026-05-01 fine
interval_case 44 2026-05-01 overdue
interval_case 007 2026-06-08 fine
interval_case 007 2026-06-07 overdue

# Thirty days without the setting, or with one that makes no sense.
for bad_interval in unset '' abc -5 0 000 1.5 30d 99999999999999999999 ' 7'; do
  interval_case "$bad_interval" 2026-05-16 fine
  interval_case "$bad_interval" 2026-05-15 overdue
done

# Dates with what shell arithmetic reads as octal, across a leap day and years.
interval_case 1000 2026-08-09 fine
interval_case 8 2026-06-08 fine
interval_case 6 2026-06-08 overdue
interval_case 107 2026-02-28 fine
interval_case 106 2026-02-28 overdue
interval_case 837 2024-02-29 fine
interval_case 836 2024-02-29 overdue
interval_case 45000 1900-03-01 overdue

# The line says how old it is and what the interval is.
repo=$(new_project)
set_last_run "$repo" '- 2026-06-01: a run'
CLAUDE_PLUGIN_OPTION_MAINTENANCE_INTERVAL_DAYS=10
export CLAUDE_PLUGIN_OPTION_MAINTENANCE_INTERVAL_DAYS
start "$repo"
unset CLAUDE_PLUGIN_OPTION_MAINTENANCE_INTERVAL_DAYS
assert_one_line '/dev-workflow:maintain' '14 days' '10 days'

# No run yet isn't overdue: no entries, an empty file, or no file.
repo=$(new_project)
start "$repo"
assert_silent
: >"$repo/docs/maintenance.md"
start "$repo"
assert_silent
rm "$repo/docs/maintenance.md"
start "$repo"
assert_silent

# Only the last entry counts, the log being newest last.
repo=$(new_project)
set_last_run "$repo" '- 2026-06-14: a run'
printf '\nSome closing words, from 2001-01-01.\n  - 2001-01-01: an indented detail\n' >>"$repo/docs/maintenance.md"
start "$repo"
assert_silent

# A last line with no line ending still counts.
repo=$(new_project)
printf -- '- 2020-01-01: a run' >>"$repo/docs/maintenance.md"
start "$repo"
assert_one_line '/dev-workflow:maintain'

# Other list markers and a bare date are still dates.
for entry in '* 2020-01-01: a run' '2020-01-01: a run' '- 2020-01-01' '- 2020-01-01 a run'; do
  repo=$(new_project)
  printf '%s\n' "$entry" >>"$repo/docs/maintenance.md"
  start "$repo"
  assert_one_line '/dev-workflow:maintain'
done

# A last entry that isn't a date says the file couldn't be read.
for entry in '- last Tuesday: a run' '- 2026-13-01: a run' '- 2026-00-10: a run' '- 2026-02-29: a run' \
  '- 2026-04-31: a run' '- 2026-06-00: a run' '- 0000-01-01: a run' '- 26-06-01: a run' \
  '- 2026-6-1: a run' '- 2026-06-01x: a run' '- 2026-06-01-02: a run' '- 06/01/2026: a run' '- '; do
  repo=$(new_project)
  set_last_run "$repo" "$entry"
  start "$repo"
  assert_one_line "couldn't read" 'docs/maintenance.md'
done

# So does a file that can't be read as one.
repo=$(new_project)
rm "$repo/docs/maintenance.md"
mkdir "$repo/docs/maintenance.md"
start "$repo"
assert_one_line "couldn't read" 'docs/maintenance.md'

# Leap years, by the rule's other two parts.
repo=$(new_project)
set_last_run "$repo" '- 1900-02-29: a run'
start "$repo"
assert_one_line "couldn't read" 'docs/maintenance.md'
repo=$(new_project)
set_last_run "$repo" '- 2000-02-29: a run'
start "$repo"
assert_one_line '/dev-workflow:maintain'

# The real date, in whichever flavour this machine has.
saved_bin=$bin
bin=$(bin_with git jq grep date)
add_script "$bin" gh 'exit 0'
repo=$(new_project)
set_last_run "$repo" '- 2001-01-01: a run'
start "$repo"
assert_one_line '/dev-workflow:maintain'
repo=$(new_project)
set_last_run "$repo" "- $(date +%Y-%m-%d): a run"
start "$repo"
assert_silent
bin=$saved_bin

# If it can't tell what today is, it says so, and only when it needs to.
for date_body in 'echo not-a-date' 'exit 1' 'echo 2026-13-45' 'echo'; do
  saved_bin=$bin
  bin=$(bin_with git jq grep)
  add_script "$bin" date "$date_body"
  add_script "$bin" gh 'exit 0'
  repo=$(new_project)
  start "$repo"
  assert_silent
  set_last_run "$repo" '- 2001-01-01: a run'
  start "$repo"
  assert_one_line "today's date" 'docs/maintenance.md'
  bin=$saved_bin
done
saved_bin=$bin
bin=$(bin_with git jq grep)
add_script "$bin" gh 'exit 0'
repo=$(new_project)
set_last_run "$repo" '- 2001-01-01: a run'
start "$repo"
assert_one_line "today's date" 'docs/maintenance.md'
bin=$saved_bin

# --- A missing tool

# gh is only looked for.
repo=$(new_project)
rm -f "$gh_log"
start "$repo"
assert_silent
assert_exit 1 test -e "$gh_log"

saved_bin=$bin
bin=$(bin_with git jq grep date)
repo=$(new_project)
start "$repo"
assert_one_line 'gh' 'brew install gh'

# jq's line stands alone: the checks that need it are left out, not reported as failed.
bin=$(bin_with git grep date)
add_script "$bin" gh 'exit 0'
repo=$(new_project)
start "$repo"
assert_one_line 'jq' 'brew install jq'
repo=$(new_project '{"pluginVersion": "0.0.1"}')
start "$repo"
assert_one_line 'jq'
repo=$(new_project 'not json')
start "$repo"
assert_one_line 'jq'

# The checks that don't need jq still run without it.
repo=$(new_project)
git -C "$repo" config --unset core.hooksPath
set_last_run "$repo" '- 2001-01-01: a run'
start "$repo"
assert_contains "$out" 'brew install jq'
assert_contains "$out" 'git config core.hooksPath .githooks'
assert_contains "$out" '/dev-workflow:maintain'
assert_exit 0 test "$(printf '%s\n' "$out" | wc -l)" -eq 3

# Without git there's nothing to read a repo with, and that's its one line.
bin=$(bin_with jq grep date)
add_script "$bin" gh 'exit 0'
repo=$(new_project)
start "$repo"
assert_one_line 'git' 'brew install git'
bin=$saved_bin

# --- A missing plugin, by name whichever marketplace it came from

missing_case() { # <name> <text of its install command>
  mc_home=$(tmp_dir)
  mc_rest=
  for mc_id in $every_plugin; do
    [ "${mc_id%%@*}" = "$1" ] || mc_rest="$mc_rest $mc_id"
  done
  # shellcheck disable=SC2086 # A list of words.
  write_registry "$mc_home" $mc_rest
  saved_home=$home
  home=$mc_home
  mc_repo=$(new_project)
  start "$mc_repo"
  home=$saved_home
  assert_one_line "$1" "$2"
}
missing_case superpowers 'claude plugin install superpowers@claude-plugins-official'
missing_case context7 'claude plugin install context7@claude-plugins-official'
missing_case serena 'claude plugin install serena@claude-plugins-official'
missing_case intent 'claude plugin install intent@intent'
missing_case ui-ux-pro-max 'claude plugin install ui-ux-pro-max@ui-ux-pro-max-skill'

# Another marketplace's copy counts.
other_home=$(tmp_dir)
write_registry "$other_home" superpowers@a context7@b serena@c intent@d ui-ux-pro-max@e
saved_home=$home
home=$other_home
repo=$(new_project)
start "$repo"
assert_silent
home=$saved_home

# The two for screens only matter in a project with screens.
no_screens='{"pluginVersion": "99.0.0", "hasScreens": false}'
screens_home=$(tmp_dir)
write_registry "$screens_home" superpowers@a context7@b serena@c
saved_home=$home
home=$screens_home
repo=$(new_project "$no_screens")
start "$repo"
assert_silent
repo=$(new_project '{"pluginVersion": "99.0.0"}')
start "$repo"
assert_silent
repo=$(new_project)
start "$repo"
assert_contains "$out" 'intent@intent'
assert_contains "$out" 'ui-ux-pro-max@ui-ux-pro-max-skill'
assert_exit 0 test "$(printf '%s\n' "$out" | wc -l)" -eq 2

# No registry at all: every one has its line.
home=$(tmp_dir)
repo=$(new_project)
start "$repo"
assert_exit 0 test "$(printf '%s\n' "$out" | wc -l)" -eq 5

# A registry it can't read says that, once, rather than calling everything missing.
for registry_text in 'not json' '' '[]' '{"version": 2}' '{"plugins": {"superpowers@a": {"scope": "user"}}}'; do
  home=$(tmp_dir)
  mkdir -p "$home/.claude/plugins"
  printf '%s' "$registry_text" >"$home/.claude/plugins/installed_plugins.json"
  repo=$(new_project)
  start "$repo"
  assert_one_line "couldn't read" 'installed_plugins.json'
done

# A plugin installed only for another project isn't installed for this one.
scoped_registry() { # <home> <project path>
  mkdir -p "$1/.claude/plugins"
  jq -n --arg path "$2" '{version: 2, plugins: {
    "superpowers@a": [{scope: "project", projectPath: $path}],
    "context7@b": [{scope: "local", projectPath: $path}],
    "serena@c": [{scope: "project", projectPath: "/elsewhere"}, {scope: "user"}],
    "intent@d": [{scope: "managed"}],
    "ui-ux-pro-max@e": [{scope: "user"}]
  }}' >"$1/.claude/plugins/installed_plugins.json"
}
home=$(tmp_dir)
repo=$(new_project)
scoped_registry "$home" "$repo"
start "$repo"
assert_silent
scoped_registry "$home" /elsewhere
start "$repo"
assert_contains "$out" 'superpowers@claude-plugins-official'
assert_contains "$out" 'context7@claude-plugins-official'
assert_exit 0 test "$(printf '%s\n' "$out" | wc -l)" -eq 2

# Installed for this project counts in its worktrees too.
scoped_registry "$home" "$(cd "$repo" && pwd -P)"
git -C "$repo" add .claude docs
git -C "$repo" commit -q -m 'chore: first'
worktree="$(tmp_dir)/the worktree"
git -C "$repo" worktree add -q -b other "$worktree"
start "$worktree"
assert_silent
home=$saved_home

# A plugin folder set elsewhere is where the registry is.
config_dir=$(tmp_dir)
mkdir -p "$config_dir/plugins"
printf '{"version": 2, "plugins": {}}\n' >"$config_dir/plugins/installed_plugins.json"
repo=$(new_project "$no_screens")
CLAUDE_CONFIG_DIR=$config_dir
export CLAUDE_CONFIG_DIR
start "$repo"
unset CLAUDE_CONFIG_DIR
assert_exit 0 test "$(printf '%s\n' "$out" | wc -l)" -eq 3

# --- A broken project file

for broken in 'not json' '[]' '{} {}'; do
  repo=$(new_project "$broken")
  start "$repo"
  assert_one_line 'dev-workflow.json' '/dev-workflow:setup'
done
repo=$(new_project)
: >"$repo/.claude/dev-workflow.json"
start "$repo"
assert_one_line 'dev-workflow.json' '/dev-workflow:setup'
repo=$(new_project)
rm "$repo/.claude/dev-workflow.json"
ln -s gone "$repo/.claude/dev-workflow.json"
start "$repo"
assert_one_line 'dev-workflow.json' '/dev-workflow:setup'

# --- All of it at once: one line each, and still exit 0

home=$(tmp_dir)
write_registry "$home" superpowers@a context7@b
repo=$(new_project '{"pluginVersion": "0.0.1", "hasScreens": false}')
git -C "$repo" config --unset core.hooksPath
set_last_run "$repo" '- 2001-01-01: a run'
start "$repo"
assert_contains "$out" 'git config core.hooksPath .githooks'
assert_contains "$out" '/dev-workflow:setup'
assert_contains "$out" 'serena@claude-plugins-official'
assert_contains "$out" '/dev-workflow:maintain'
assert_exit 0 test "$(printf '%s\n' "$out" | wc -l)" -eq 4
home=$saved_home

# --- A missing library in the plugin doesn't stop the session

copy="$(tmp_dir)/the plugin"
mkdir -p "$copy/scripts"
cp "$hook" "$copy/scripts/"
repo=$(new_project)
start "$repo" "$copy/scripts/hook-session-start.sh"
assert_silent

# --- Speed: under a second, with every check running. A busy machine only adds to the time,
# so the best of a few runs is the one that measures this script.

repo=$(new_project)
set_last_run "$repo" '- 2026-06-14: a run'
fastest=
for _ in 1 2 3; do
  began=$(date +%s)
  start "$repo"
  finished=$(date +%s)
  taken=$((finished - began))
  if [ -z "$fastest" ] || [ "$taken" -lt "$fastest" ]; then
    fastest=$taken
  fi
done
# Whole seconds, so a run that crosses a second's edge reads as 1 however short it was.
[ "$fastest" -le 1 ] || _assert_fail "the check took $fastest seconds"
