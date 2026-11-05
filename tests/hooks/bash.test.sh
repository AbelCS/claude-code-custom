#!/bin/sh
# shellcheck disable=SC2016 # Dollars and backticks in quotes are commands for the hook.
#
# Tests the Bash rules on hooks being skipped, merging after tests, database resets and the
# project's lists, and how the hook itself runs and fails. Local merges are in
# bash-merge.test.sh, and the rules on gh commands in bash-gh.test.sh.

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
# shellcheck source=tests/lib/assert.sh
. "$ROOT/tests/lib/assert.sh"
# shellcheck source=tests/lib/hook.sh
. "$ROOT/tests/lib/hook.sh"
# shellcheck source=tests/lib/bash-rules.sh
. "$ROOT/tests/lib/bash-rules.sh"

# --- --no-verify

rule deny 'git commit --no-verify -m "feat: x (#1)"' '--no-verify'
rule deny 'git commit -n -m "feat: x (#1)"' '--no-verify'
rule deny 'git push --no-verify' '--no-verify'
rule deny 'git push origin feat/1-x --no-verify'
rule deny 'git commit --amend --no-verif'
rule none 'git commit -m "docs: explain --no-verify (#1)"'

# Combined short flags, where n means no-verify on commit.
rule deny 'git commit -anm "feat: x (#1)"'
rule deny 'git commit -an -m "feat: x (#1)"'
rule none 'git commit -am "feat: x (#1)"'
rule none 'git commit -m "-n"'
rule none 'git commit -m"-n"'
rule none 'git commit -m -n'
rule none 'git commit -F -n'
rule none 'git commit --message "-n"'
rule none 'git commit --message=--no-verify'
rule none 'git commit --author "-n" -m "feat: x (#1)"'
rule none 'git commit -uno -m "feat: x (#1)"'
rule none 'git commit -m "feat: x (#1)" -- -n'

# On push, -n is a dry run.
rule none 'git push -n'
rule none 'git push -n origin feat/1-x'
rule none 'git push --dry-run'

# A message from a heredoc, as commits are usually written.
rule_stdin none <<'COMMAND'
git commit -m "$(cat <<'EOF'
feat: x (#1)

It's about -n and --no-verify.
EOF
)"
COMMAND
rule_stdin deny '--no-verify' <<'COMMAND'
git commit --no-verify -m "$(cat <<'EOF'
feat: x (#1)
EOF
)"
COMMAND

# Text that only mentions it.
rule none 'git log --grep=--no-verify'
rule none 'git log --grep "--no-verify"'
rule none 'git log -n 3'
rule none 'git diff -n'
rule none 'echo git commit --no-verify'
rule none 'git commit -m "feat: x (#1)" && echo --no-verify'

# --- Merging after tests

rule deny 'npm run check && gh pr merge 1 --squash --body ""' 'test'
rule deny 'npx vitest; gh pr merge 1 --squash --body ""' 'test'
rule none 'npm run check'
rule none 'npx vitest'
rule none 'gh pr merge 1 --squash --subject "x" --body "" && git pull'

# Each of check, verify and testCommands, and a merge of either kind.
rule deny 'scripts/verify && gh pr merge 1 --squash --body ""'
rule deny './scripts/verify && gh pr merge 1 --squash --body ""'
rule deny "\"$repo/scripts/verify\" && gh pr merge 1 --squash --body \"\""
rule deny 'npm run check && git merge main'
rule deny 'npx vitest run && git merge main'

# A whole-word prefix of the command.
rule deny 'npm run check -- --x && gh pr merge 1 --squash --body ""'
rule deny 'npx vitest run src && gh pr merge 1 --squash --body ""'
rule none 'npm run check:types && gh pr merge 1 --squash --body ""'
rule none 'npm run checking && gh pr merge 1 --squash --body ""'
rule none 'npm run && gh pr merge 1 --squash --body ""'
rule none 'npx vitest-other && gh pr merge 1 --squash --body ""'

# Wherever the test sits, and however the shell gets to the merge.
rule deny 'npm run check || gh pr merge 1 --squash --body ""'
rule deny 'npm run check | cat; gh pr merge 1 --squash --body ""'
rule deny 'npm run check 2>&1 | tee out; gh pr merge 1 --squash --body ""'
rule deny 'if (npm run check); then gh pr merge 1 --squash --body ""; fi'
rule deny 'if npm run check; then gh pr merge 1 --squash --body ""; fi'
rule deny '(npx vitest) && gh pr merge 1 --squash --body ""'
rule deny 'npx vitest
gh pr merge 1 --squash --body ""'
rule deny 'echo first && npm run check && echo again && gh pr merge 1 --squash --body ""'
rule deny 'echo "$(npx vitest)" && gh pr merge 1 --squash --body ""'
rule deny 'env CI=1 npm run check && gh pr merge 1 --squash --body ""'
rule deny 'CI=1 npm run check && gh pr merge 1 --squash --body ""'
rule deny '"npm" run "check" && gh pr merge 1 --squash --body ""'
rule deny 'npm run check && env A=1 gh pr merge 1 --squash --body ""'
rule deny 'npm run check && gh -R o/r pr merge 1 --squash --body ""'

# Run with a time limit, at low priority or by a shell.
rule deny 'timeout 600 npm run check && gh pr merge 1 --squash --body ""' 'test'
rule deny 'timeout -k 5 600 npx vitest; gh pr merge 1 --squash --body ""' 'test'
rule deny 'nice npm run check && gh pr merge 1 --squash --body ""' 'test'
rule deny 'nice -n 5 npm run check && gh pr merge 1 --squash --body ""' 'test'
rule deny 'sh scripts/verify && gh pr merge 1 --squash --body ""' 'test'
rule deny 'bash scripts/verify && gh pr merge 1 --squash --body ""' 'test'
rule deny 'sh ./scripts/verify --fast && gh pr merge 1 --squash --body ""' 'test'
rule deny 'bash -e scripts/verify && gh pr merge 1 --squash --body ""' 'test'
rule none 'timeout 600 npm run check:types && gh pr merge 1 --squash --body ""'
rule none 'sh scripts/other && gh pr merge 1 --squash --body ""'
rule none 'timeout 600 npm run check'
rule none 'sh scripts/verify'
rule deny 'timeout 5 gh pr merge 1 --squash' '--body'
rule deny 'nice git commit --no-verify'
rule ask 'timeout 5 npm run db:reset'
rule none 'sh scripts/gh pr merge 1'

# A redirection joined to its word.
rule deny 'npm run check>out && gh pr merge 1 --squash --body ""' 'test'
rule deny 'npm run check>out 2>&1; gh pr merge 1 --squash --body ""' 'test'
rule deny 'git commit --no-verify>out' '--no-verify'
rule deny 'git commit -n>out' '--no-verify'
rule deny 'git push --no-verify&>out' '--no-verify'
rule none 'gh pr merge 1 --squash --body "">/dev/null'
rule none "gh pr merge 1 --squash --body ''>/dev/null"
rule none 'gh pr merge 1 --squash --body="">/dev/null'
rule deny 'gh pr merge 1 --squash --body "x">/dev/null' '--body'
rule ask 'npm run db:reset>out'
rule deny 'gh pr create --title "add stuff" --body "Closes #1">out' 'title'
rule none 'gh pr create --title "feat: x" --body "Closes #1">out'

# A merge before the test, what isn't a merge, and what only mentions a test.
rule none 'gh pr merge 1 --squash --body "" && npm run check'
rule none 'gh pr merge 1 --squash --body ""; npx vitest'
rule none 'npm run check && gh pr view 1'
rule none 'npm run check && git merge --abort'
rule none 'npm run check && git merge --ff-only origin/main'
rule none 'npm run check && gh pr merge 1 --disable-auto'
rule none 'echo "npm run check" && gh pr merge 1 --squash --body ""'
rule none 'npm run check && echo "gh pr merge 1"'

# --- Command prefixes

# Each prefix is in command-words.test.sh. Words are read once, so these few show that
# every rule reads them.
prefix='env A=1'
rule deny "$prefix gh pr merge 1 --squash" '--body'
rule none "$prefix gh pr merge 1 --squash --body \"\""
rule deny "$prefix git commit --no-verify"
rule none "$prefix git commit -m \"feat: x (#1)\""
rule deny "$prefix gh pr create --title \"add stuff\" --body \"Closes #1\""
rule ask "$prefix npm run db:reset"
rule deny "$prefix npm run check && gh pr merge 1 --squash --body \"\""
rule deny 'sudo -u bob git commit --no-verify'
rule deny '2>/dev/null gh pr merge 1 --squash' '--body'

# Asking what a command is doesn't run it.
rule none 'command -v gh'
rule none 'command -v gh pr merge 1'
rule none 'command -V git merge x'

# Quoted and escaped names, and paths to the tools.
rule deny '"gh" pr merge 1'
rule deny "'gh' 'pr' 'merge' 1"
rule deny '"gh" "pr" merge 1 --squash'
rule deny 'g\h pr merge 1'
rule deny '/opt/homebrew/bin/gh pr merge 1'
rule deny '"git" commit --no-verify'
rule deny '/usr/bin/git commit -n'

# The tools' own options before the subcommand.
rule deny 'gh -R o/r pr merge 1 --squash'
rule deny 'gh --repo o/r pr merge 1 --squash'
rule deny 'gh --repo=o/r pr merge 1 --squash'
rule deny 'gh -Ro/r pr merge 1 --squash'
rule deny 'gh pr -R o/r merge 1 --squash'
rule deny 'gh pr merge -R o/r 1 --squash'
rule none 'gh -R o/r pr merge 1 --squash --body ""'
rule none 'gh pr merge -R o/r 1 --squash --body ""'
rule none 'gh pr merge 1 -R o/r --squash --body ""'
rule deny 'gh -R o/r pr create --title "add stuff" --body "Closes #1"'
rule deny 'git -c k=v commit --no-verify'
rule deny 'git -C path commit -n -m "feat: x (#1)"'
rule deny 'git --no-pager commit --no-verify'
rule deny 'git --git-dir .git --work-tree=. push --no-verify'
rule deny 'git -c a=b -C path -c c=d commit -anm "feat: x (#1)"'
rule none 'git -c commit.gpgsign=false commit -m "feat: x (#1)"'
rule none 'git -C commit log'

on_branch main
rule deny 'git -C path merge x'
rule deny 'git -c k=v merge x'
rule deny 'env A=1 git merge x'
rule deny 'sudo git merge x'
rule deny 'exec git merge x'
rule deny '"git" merge x'
rule none 'git -C path merge --abort'
on_branch feat/1-x

printf 'Why.\n\nCloses #1\n' >"$repo/clean.md"

# --- Database resets

rule ask 'npm run db:reset' 'reset'
rule ask 'DEBUG=1 npm run db:reset'
rule ask 'dropdb app'
rule ask 'docker compose down -v'
rule none 'npm run db:migrate'

rule ask 'npm run db:reset -- --force'
rule ask 'echo first && npm run db:reset'
rule ask 'sudo -u postgres dropdb app'
rule ask '/usr/local/bin/dropdb app'
rule ask 'docker compose down --volumes'
rule ask 'docker compose -f a.yml --project-name x down --remove-orphans -v'
rule ask 'docker-compose down -v'
rule none 'npm run db:reset:test'
rule none 'npm run db'
rule none 'docker compose down'
rule none 'docker compose up -v'
rule none 'docker compose logs -v down'
rule none 'dropdbx app'
rule none 'echo dropdb app'
rule none 'git docker compose down -v'
rule none 'gh pr create --help docker compose down -v'
rule none 'grep "npm run db:reset" notes.md'

# A reset never hides a denial later in the same command, and neither way round.
rule deny 'npm run db:reset && git commit --no-verify'
rule deny 'git commit --no-verify; npm run db:reset'

# Several parts in a configured command count separately, except moving to a folder.
parts="$(tmp_dir)/parts"
new_repo "$parts"
mkdir -p "$parts/.claude"
cat >"$parts/.claude/dev-workflow.json" <<'JSON'
{
  "commands": { "check": "cd web && npm run lint && npm test" },
  "databaseResetCommands": ["cd db && ./reset.sh"]
}
JSON
CLAUDE_PROJECT_DIR=$parts
rule deny 'npm test && gh pr merge 1 --squash --body ""'
rule deny 'cd web && npm run lint && npm test && gh pr merge 1 --squash --body ""'
rule none 'cd web && gh pr merge 1 --squash --body ""'
rule ask 'cd db && ./reset.sh'
rule ask './reset.sh'
rule none 'cd db'

# Lists are matched past git's own options, on either side.
git_lists="$(tmp_dir)/git lists"
new_repo "$git_lists"
mkdir -p "$git_lists/.claude"
cat >"$git_lists/.claude/dev-workflow.json" <<'JSON'
{
  "commands": { "check": "git -C web diff --stat" },
  "testCommands": ["git diff --check"],
  "databaseResetCommands": ["git clean -fdx", "git --no-pager -C db reset --hard"]
}
JSON
CLAUDE_PROJECT_DIR=$git_lists
rule deny 'git diff --check && gh pr merge 1 --squash --body ""' 'test'
rule deny 'git -C sub diff --check && gh pr merge 1 --squash --body ""' 'test'
rule deny 'git -C "a b" -C sub diff --check && gh pr merge 1 --squash --body ""' 'test'
rule deny 'git -C "$X" diff --check && gh pr merge 1 --squash --body ""' 'test'
rule deny 'git -c k=v diff --check && gh pr merge 1 --squash --body ""' 'test'
rule deny 'git --no-pager -C sub diff --check -- x && gh pr merge 1 --squash --body ""' 'test'
rule deny 'git diff --stat && gh pr merge 1 --squash --body ""' 'test'
rule deny 'git -C other diff --stat && gh pr merge 1 --squash --body ""' 'test'
rule none 'git -C sub diff --check'
rule none 'git -C sub diff --cached && gh pr merge 1 --squash --body ""'
rule none 'git -C diff --check && gh pr merge 1 --squash --body ""'
rule ask 'git clean -fdx'
rule ask 'git -C sub clean -fdx'
rule ask 'git -c k=v -C sub clean -fdx'
rule ask 'git reset --hard'
rule ask 'git -C sub reset --hard origin/main'
rule none 'git -C sub clean -n'
rule none 'git -C sub reset --soft'

# An unclosed quote in one list can't take in the other.
open_quote="$(tmp_dir)/open quote"
new_repo "$open_quote"
mkdir -p "$open_quote/.claude"
cat >"$open_quote/.claude/dev-workflow.json" <<'JSON'
{
  "testCommands": ["npm test \"x"],
  "databaseResetCommands": ["./reset.sh"]
}
JSON
CLAUDE_PROJECT_DIR=$open_quote
rule ask './reset.sh'
rule none 'dropfoo'

# This hook runs before every Bash call, so what it starts is held to a budget: the gate's
# two reads, the command, one read of both lists, and two passes each over lists and command.
counting_tools=$(tmp_dir)
export COUNT_LOG="$counting_tools/log"
for tool in jq awk; do
  cat >"$counting_tools/$tool" <<COUNTER
#!/bin/sh
echo $tool >>"\$COUNT_LOG"
exec "$(command -v "$tool")" "\$@"
COUNTER
  chmod +x "$counting_tools/$tool"
done
ln -s "$(command -v cat)" "$counting_tools/cat"
CLAUDE_PROJECT_DIR=$repo
HOOK_PATH=$counting_tools:/nothing
_hook_run "$hook" "$(bash_input 'ls')" || _assert_fail "the counted hook failed"
unset HOOK_PATH
assert_exit 0 test "$(grep -c jq "$COUNT_LOG")" -eq 4
assert_exit 0 test "$(grep -c awk "$COUNT_LOG")" -eq 4

# With no lists at all, the always-on rules still hold.
minimal="$(tmp_dir)/minimal"
new_repo "$minimal"
mkdir -p "$minimal/.claude"
printf '{}\n' >"$minimal/.claude/dev-workflow.json"
CLAUDE_PROJECT_DIR=$minimal
rule ask 'dropdb app'
rule deny 'git commit -n'
rule none 'npm test && gh pr merge 1 --squash --body ""'
rule none 'npm run db:reset'

# Lists that aren't lists can't be trusted to be complete.
broken="$(tmp_dir)/broken"
new_repo "$broken"
mkdir -p "$broken/.claude"
CLAUDE_PROJECT_DIR=$broken
for contents in \
  '{"testCommands": "npm test"}' \
  '{"databaseResetCommands": {"a": 1}}' \
  '{"commands": "npm test"}'; do
  printf '%s\n' "$contents" >"$broken/.claude/dev-workflow.json"
  rule deny 'echo hi' 'dev-workflow.json'
done
printf '{"commands":\n' >"$broken/.claude/dev-workflow.json"
rule deny 'echo hi' 'dev-workflow.json'

CLAUDE_PROJECT_DIR=$repo

# --- Commands the hook has nothing to say about

rule none 'ls -la'
rule none ''
rule none 'git status'
assert_decision none "$hook" "$(tool_input Bash '{}')"

# A command it can't read as text is denied, and the hook still prints one decision.
assert_decision deny "$hook" '{"tool_name": "Bash", "tool_input": "not an object"}'
assert_decision deny "$hook" 'not json'

# --- Doing nothing outside a project

bare="$(tmp_dir)/bare"
mkdir "$bare"
no_tools=$(tmp_dir)
CLAUDE_PROJECT_DIR=$bare
for command in \
  'git commit --no-verify' \
  'gh pr merge 1' \
  'dropdb app'; do
  rule none "$command"
  # Without jq too, and nothing outside the shell runs before the gate.
  HOOK_PATH=$no_tools
  rule none "$command"
  unset HOOK_PATH
done
CLAUDE_PROJECT_DIR=$repo

# In a project, no jq blocks.
HOOK_PATH=$no_tools
rule deny 'ls' 'jq'
unset HOOK_PATH

# The hook runs from another folder and by a relative path.
assert_exit 0 test -x "$hook"
input=$(bash_input 'git commit -n')
assert_contains "$(cd "$plugin/scripts" && printf '%s' "$input" | sh hook-bash.sh)" '"deny"'
assert_contains "$(cd "$plugin" && printf '%s' "$input" | sh scripts/hook-bash.sh)" '"deny"'

# --- What the hook relies on, missing or failing, blocks

fake_tools=$(tmp_dir)
for tool in git jq awk sed tr cat; do
  ln -s "$(command -v "$tool")" "$fake_tools/$tool"
done
cat >"$fake_tools/grep" <<'FAKE'
#!/bin/sh
exit 2
FAKE
chmod +x "$fake_tools/grep"
HOOK_PATH=$fake_tools
rule deny 'gh pr comment 1 --body "Clean"' 'attribution'
rule deny 'gh pr comment 1 --body-file clean.md' 'attribution'
unset HOOK_PATH

cat >"$fake_tools/grep" <<FAKE
#!/bin/sh
exec "$(command -v grep)" "\$@"
FAKE
rm "$fake_tools/awk"
cat >"$fake_tools/awk" <<'FAKE'
#!/bin/sh
exit 2
FAKE
chmod +x "$fake_tools/awk"
HOOK_PATH=$fake_tools
rule deny 'ls' 'read'
unset HOOK_PATH

# Any stage of reading the text failing means it can't be told, whatever grep says after.
for failing in tr sed; do
  for with_output in '' 1; do
    stubs=$(tmp_dir)
    for tool in git jq awk sed tr cat grep; do
      ln -s "$(command -v "$tool")" "$stubs/$tool"
    done
    failing_tool "$stubs" "$failing" "$with_output"
    HOOK_PATH=$stubs
    rule deny "gh pr comment 7 --body 'Generated with Claude Code'" 'attribution'
    rule deny "gh pr comment 7 --body 'Clean'" 'attribution'
    rule deny "gh issue create --title x --body 'Clean'" 'attribution'
    rule deny "gh api repos/o/r/issues -f body='Clean'" 'attribution'
    rule deny "gh pr merge 7 --squash --subject 'chore: x (#2)' --body ''" 'attribution'
    unset HOOK_PATH
  done
done
# The raw command is read separately, with its own stage.
stubs=$(tmp_dir)
for tool in git jq awk sed cat grep; do
  ln -s "$(command -v "$tool")" "$stubs/$tool"
done
cat >"$stubs/tr" <<FAKE
#!/bin/sh
case \$1 in
  -d | \"* | \'*) exit 1 ;;
esac
exec "$(command -v tr)" "\$@"
FAKE
chmod +x "$stubs/tr"
HOOK_PATH=$stubs
rule deny "BODY='Generated with Claude Code'; gh pr comment 7 --body \"\$BODY\"" 'attribution'
rule deny "BODY='Generated with Claude Code'; gh api repos/o/r/issues -f body=\"\$BODY\"" 'attribution'
unset HOOK_PATH

# A heredoc the shell can't create leaves the hook's loop unrun, which isn't a clean command.
no_temp="$(tmp_dir)/no-temp"
mkdir "$no_temp"
chmod 555 "$no_temp"
real_tmpdir=${TMPDIR:-}
TMPDIR=$no_temp
export TMPDIR
rule deny 'git commit --no-verify'
TMPDIR=$real_tmpdir
without_temp=$(hook_without_temp_files "$hook")
if [ -n "$without_temp" ]; then
  for command in 'git commit --no-verify' 'gh pr merge 1' 'ls'; do
    assert_decision deny "$without_temp" "$(bash_input "$command")"
    assert_contains "$(reason_of "$without_temp" "$(bash_input "$command")")" "can't be checked"
  done
fi
chmod 755 "$no_temp"

partial="$(tmp_dir)/partial"
mkdir -p "$partial/scripts/lib"
cp "$hook" "$partial/scripts/"
cp "$plugin/scripts/lib/"* "$partial/scripts/lib/"
rule_partial() {
  assert_decision deny "$partial/scripts/hook-bash.sh" "$(bash_input 'ls')"
  assert_contains "$(reason_of "$partial/scripts/hook-bash.sh" "$(bash_input 'ls')")" "$1"
}
rule_partial 'dw-lib.sh'
mkdir -p "$partial/skills/setup/templates/githooks"
cp "$plugin/skills/setup/templates/githooks/dw-lib.sh" "$partial/skills/setup/templates/githooks/"
assert_decision none "$partial/scripts/hook-bash.sh" "$(bash_input 'ls')"
rm "$partial/scripts/lib/command-words.awk"
assert_decision deny "$partial/scripts/hook-bash.sh" "$(bash_input 'ls')"
