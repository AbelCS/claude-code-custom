#!/bin/sh
# shellcheck disable=SC2016 # Dollars and backticks in quotes are commands for the hook.
#
# Tests the rules on Bash commands, as a table of commands and the decision each gets,
# run through the real hook in a real repo.

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
# shellcheck source=tests/lib/assert.sh
. "$ROOT/tests/lib/assert.sh"
# shellcheck source=tests/lib/hook.sh
. "$ROOT/tests/lib/hook.sh"

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

# --- Local merges into the default branch

on_branch main
rule deny 'git merge feat/1-x' 'main'
rule deny 'git merge'
rule deny 'git merge --no-ff feat/1-x'
rule deny 'git merge -m "--abort" feat/1-x'
rule deny 'git merge origin/main'
rule deny 'git merge --ff-only feat/1-x'
rule deny 'git merge --ff-only origin/main feat/1-x'
rule deny 'git merge --ff-only --no-ff origin/main'
rule deny 'git merge -- feat/1-x'
rule deny 'cd sub && git merge feat/1-x'

# Updating and getting out of a merge.
rule none 'git merge --ff-only origin/main'
rule none 'git merge --ff-only'
rule none 'git merge --ff-only @{u}'
rule none 'git merge --abort'
rule none 'git merge --continue'
rule none 'git merge --quit'
rule none 'git merge --help'
rule none 'git pull'
rule none 'git pull --ff-only'
rule none 'git log --merges'
rule none 'git log --grep="git merge x"'
rule none 'echo git merge feat/1-x'

on_branch feat/1-x
rule none 'git merge main'
rule none 'git merge feat/2-y'

# The default branch comes from origin/HEAD when there is one.
git -C "$repo" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/trunk
on_branch trunk
rule deny 'git merge feat/1-x' 'trunk'
rule none 'git merge --ff-only origin/trunk'
rule deny 'git merge --ff-only origin/main'
on_branch main
rule none 'git merge feat/1-x'
git -C "$repo" symbolic-ref --delete refs/remotes/origin/HEAD

# A detached HEAD is on no branch.
git -C "$repo" update-ref refs/heads/main HEAD 2>/dev/null
git -C "$repo" switch -q --detach main
rule none 'git merge feat/1-x'
on_branch feat/1-x

# --- Moving to another branch earlier in the command

rule deny 'git checkout main && git merge feat/1-x' 'main'
rule deny 'git switch main && git merge --no-ff feat/1-x && git push' 'main'
rule deny 'git switch main; git merge feat/1-x' 'main'
rule deny 'git checkout -q main && git merge feat/1-x' 'main'
rule deny 'git switch -f main 2>/dev/null && git merge feat/1-x' 'main'
rule deny 'env A=1 git switch main && sudo git merge feat/1-x' 'main'
rule deny 'git -c a=b switch main && git merge feat/1-x' 'main'
rule deny 'git switch feat/2-y && git switch main && git merge feat/1-x' 'main'
rule deny 'git switch -c main && git merge feat/1-x' 'main'
rule deny 'git checkout -b main && git merge feat/1-x' 'main'
rule deny 'git checkout -B main origin/main && git merge feat/1-x' 'main'
rule none 'git switch main'
rule none 'git checkout main'
rule none 'git switch main && git pull --ff-only'
rule none 'git switch main && git merge --ff-only origin/main'
rule none 'git switch main && git merge --abort'
rule none 'git merge feat/2-y && git switch main'
rule none 'git switch main && git switch feat/2-y && git merge main'
rule none 'git switch --help && git merge main'
rule none 'git checkout --help && git merge main'
rule none 'git log --grep="git switch main" && git merge main'
rule none 'echo git switch main && git merge main'

on_branch main
rule none 'git switch feat/1-x && git merge main'
rule none 'git checkout feat/1-x && git merge main'
rule none 'git checkout -b new && git merge feat/1-x'
rule none 'git checkout -bnew && git merge feat/1-x'
rule none 'git checkout -B new main && git merge feat/1-x'
rule none 'git checkout --orphan new && git merge feat/1-x'
rule none 'git switch -c new && git merge feat/1-x'
rule none 'git switch -c new main && git merge feat/1-x'
rule none 'git switch --create new && git merge feat/1-x'
rule none 'git switch -C new && git merge feat/1-x'
rule none 'git switch --orphan new && git merge feat/1-x'
rule none 'git switch --detach && git merge feat/1-x'
rule none 'git switch -d v1 && git merge feat/1-x'
rule none 'git checkout --detach && git merge feat/1-x'

# A checkout of paths doesn't move, so this is still on main.
rule deny 'git checkout -- file && git merge feat/1-x' 'main'
rule deny 'git checkout feat/1-x -- file && git merge feat/1-x' 'main'
rule deny 'git checkout feat/1-x file && git merge feat/1-x' 'main'
rule deny 'git checkout one two && git merge feat/1-x' 'main'
rule deny 'git checkout sub && git merge feat/1-x' 'main'
rule deny 'git checkout . && git merge feat/1-x' 'main'
rule deny 'git checkout -p && git merge feat/1-x' 'main'
rule deny 'git checkout --ours file && git merge feat/1-x' 'main'
rule deny 'git checkout && git merge feat/1-x' 'main'
on_branch feat/1-x
rule none 'git checkout -- file && git merge main'
rule none 'git checkout main -- file && git merge main'
rule none 'git checkout main file && git merge main'
rule none 'git checkout sub && git merge main'
rule none 'git checkout . && git merge main'
rule none 'git checkout -p && git merge main'

# Where it can't be told, a later merge has to run on its own.
for move in \
  'git switch "$BRANCH"' \
  'git switch $(git rev-parse --abbrev-ref @{u})' \
  'git switch -' \
  'git switch @{-1}' \
  'git switch -c "$BRANCH"' \
  'git switch -t origin/main' \
  'git switch --track origin/main' \
  'git checkout "$BRANCH"' \
  'git checkout -' \
  'git checkout @{-1}' \
  'git checkout -b "$BRANCH"' \
  'git checkout -t origin/main' \
  'git checkout not-a-branch-or-file' \
  'git checkout HEAD~1' \
  'git checkout origin/main'; do
  rule deny "$move && git merge feat/2-y" 'separately'
done
rule none 'git switch -'
rule none 'git checkout "$BRANCH"'
rule none 'git checkout - && git merge --abort'
rule none 'git switch "$BRANCH" && git merge --ff-only origin/main'
# A later move that can be told settles it.
rule none 'git switch - && git switch feat/2-y && git merge main'
rule deny 'git switch - && git switch main && git merge feat/2-y' 'main'

# --- The session's folder decides the branch, as it can be a worktree

worktree="$(tmp_dir)/a worktree"
git -C "$repo" worktree add -q "$worktree" feat/2-y
mkdir "$worktree/sub"
other="$(tmp_dir)/other repo"
new_repo "$other"
git -C "$other" commit -q --allow-empty -m 'chore: start'
git -C "$other" branch feat/9-z
mkdir "$other/sub"

# The project on main, the session in a worktree on a work branch.
on_branch main
cd "$worktree" || exit 1
rule none 'git merge main'
rule none 'git merge feat/1-x'
cd "$worktree/sub" || exit 1
rule none 'git merge main'
cd "$worktree" || exit 1
rule deny 'git switch main && git merge feat/1-x' 'main'
rule deny "git -C \"$repo\" merge feat/1-x" 'main'
cd "$repo" || exit 1
rule deny 'git merge feat/1-x' 'main'
rule none "git -C \"$worktree\" merge main"
rule none 'git -C "'"$worktree"'" merge main'

# And the reverse.
on_branch feat/1-x
git -C "$worktree" symbolic-ref HEAD refs/heads/main
cd "$worktree" || exit 1
rule deny 'git merge feat/2-y' 'main'
rule none 'git switch feat/2-y && git merge main'
rule none "git -C \"$repo\" merge main"
cd "$repo" || exit 1
rule none 'git merge main'
rule deny "git -C \"$worktree\" merge feat/1-x" 'main'
git -C "$worktree" symbolic-ref HEAD refs/heads/feat/2-y

# Without a usable cwd, the project's folder.
on_branch main
no_cwd=$(jq -n '{tool_name: "Bash", tool_input: {command: "git merge feat/1-x"}}')
assert_decision deny "$hook" "$no_cwd"
relative_cwd=$(jq -n '{tool_name: "Bash", tool_input: {command: "git merge feat/1-x"}, cwd: "sub"}')
assert_decision deny "$hook" "$relative_cwd"
gone_cwd=$(jq -n '{tool_name: "Bash", tool_input: {command: "git merge feat/1-x"}, cwd: "/no/such/folder"}')
assert_decision deny "$hook" "$gone_cwd"
on_branch feat/1-x
assert_decision none "$hook" "$no_cwd"

# -C judges the folder it names, from the session's folder, while it can be read.
rule deny "git -C \"$other\" merge x" 'main'
rule deny "git -C \"$other/sub\" merge x" 'main'
rule deny "git -C \"$other\" -C sub merge x" 'main'
rule none 'git -C path merge main'
rule none 'git -C sub merge main'
rule none "git -C \"$other\" merge --abort"
git -C "$other" symbolic-ref HEAD refs/heads/feat/9-z
rule none "git -C \"$other\" merge main"
on_branch main
rule none "git -C \"$other\" merge main"
rule deny 'git -C path merge x' 'main'
rule deny 'git -C sub merge x' 'main'

# That folder's own default branch, and its own moves.
git -C "$other" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/trunk
git -C "$other" symbolic-ref HEAD refs/heads/trunk
rule deny "git -C \"$other\" merge x" 'trunk'
git -C "$other" symbolic-ref --delete refs/remotes/origin/HEAD
git -C "$other" symbolic-ref HEAD refs/heads/feat/9-z
on_branch feat/1-x
rule none "git -C \"$other\" switch main && git merge main"
rule deny "git -C \"$other\" switch main && git -C \"$other\" merge x" 'main'
rule deny "git -C \"$other\" switch main && git -C \"$other/sub\" merge x" 'main'
rule deny 'git switch main && git -C sub merge x' 'main'
on_branch main
rule none 'git -C "'"$other"'" switch feat/9-z && git -C "'"$other"'" merge main'
rule deny 'git -C "'"$other"'" switch feat/9-z && git merge x' 'main'
on_branch feat/1-x

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

# --- gh pr merge flags

rule deny 'gh pr merge 1 --squash' '--body'
rule deny 'gh pr merge 1 --merge --body ""' '--squash'
rule deny 'gh pr merge 1 --rebase --body ""'
rule deny 'gh pr merge 1 --squash --merge --body ""'
rule deny 'gh pr merge 1 --body ""'
rule deny 'gh pr merge 1 --squash --body "text"'
rule deny 'gh pr merge 1 --squash --body-file b.md'
rule deny 'gh pr merge 1 --squash --subject "--body"'
rule deny 'gh pr merge 1 --subject "--squash" --body ""'
rule deny 'gh pr merge'
rule none 'gh pr merge 1 --squash --body ""'
rule none "gh pr merge 1 --squash --body ''"
rule none 'gh pr merge 1 --squash --body=""'
rule none 'gh pr merge 1 --squash --body='
rule none 'gh pr merge 1 --squash --subject "--merge" --body "" --delete-branch'
rule none 'gh pr merge 1 -s -b ""'
rule none 'gh pr merge 1 -sd -b ""'
rule none 'gh pr merge 1 --squash --body "" 2>&1'
rule none 'gh pr merge 1 --disable-auto'
rule none 'gh pr merge --help'
rule none 'gh pr view 1'
rule none 'gh pr list --search "gh pr merge"'
rule none 'echo "gh pr merge 1"'
rule none 'grep "gh pr merge" notes.md'
rule none 'gh pr comment 1 --body "explains gh pr merge"'

# A subject becomes a commit that no git hook sees.
rule deny 'gh pr merge 1 --squash --subject "Generated with Claude Code" --body ""' 'attribution'

# --- Command prefixes

# Each prefix is in command-words.test.sh. Words are read once, so these few show that
# every rule reads them.
for prefix in 'env A=1' 'sudo -u bob' '2>/dev/null'; do
  rule deny "$prefix gh pr merge 1 --squash" '--body'
  rule none "$prefix gh pr merge 1 --squash --body \"\""
  rule deny "$prefix git commit --no-verify"
  rule none "$prefix git commit -m \"feat: x (#1)\""
  rule deny "$prefix gh pr create --title \"add stuff\" --body \"Closes #1\""
  rule ask "$prefix npm run db:reset"
  rule deny "$prefix npm run check && gh pr merge 1 --squash --body \"\""
done

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

# --- Pull request titles and closing keywords

rule deny 'gh pr create --title "add stuff" --body "Closes #1"' 'title'
rule deny 'gh pr create --title "feat: x" --body "no keyword"' 'closing keyword'
rule none 'gh pr create --title "feat: x" --body "Closes #1"'
rule deny 'gh pr create --title "feat: x" --body "Closes #1\n\nGenerated with Claude Code"' 'attribution'

for title in \
  'feat(api)!: add thing' \
  'fix(scope): y (#12)' \
  'chore: z'; do
  rule none "gh pr create --title \"$title\" --body \"Closes #1\""
done
for title in \
  'Merge branch x' \
  'nonsense: y' \
  'feat:' \
  'feat: ' \
  'fixup! feat: x' \
  ''; do
  rule deny "gh pr create --title \"$title\" --body \"Closes #1\"" 'title'
done
rule deny 'gh pr create --body "Closes #1"' 'title'
rule deny 'gh pr create --title "feat: x"' 'closing keyword'
rule deny 'gh pr create' 'title'
rule deny 'gh pr create --title "Oops
feat: x" --body "Closes #1"' 'title'

# Every way of writing the flags.
rule none 'gh pr create -t "feat: x" -b "Closes #1"'
rule none 'gh pr create -t"feat: x" -b"Closes #1"'
rule none 'gh pr create --title="feat: x" --body="Closes #1"'
rule none 'gh pr create -dt "feat: x" -b "Closes #1"'
rule none "gh pr create --title 'feat: x' --body 'Closes #1'"
rule none 'gh pr create --title "feat: x" --body $'"'"'Why.\n\nCloses #1'"'"
rule none 'gh pr create --title "feat: x" --body "Why.\n\nCloses #1"'
rule none 'gh pr create --title "feat: x" --body "Why.

Closes #1"'
rule deny 'gh pr create -t "add stuff" -b "Closes #1"' 'title'
rule deny 'gh pr create --label "--title" --title "add stuff" --body "Closes #1"' 'title'
rule deny 'gh pr create --title "feat: x" --body "--title"' 'closing keyword'

# GitHub's closing keywords, in any case, and what isn't one.
for keyword in \
  'closes #1' 'Close #1' 'Closed #1' 'FIXES #1' 'Fix #1' 'fixed #1' \
  'Resolves #12' 'resolve #1' 'resolved #1' 'Closes: #1' 'Closes o/r#1'; do
  rule none "gh pr create --title \"feat: x\" --body \"Why.
$keyword\""
done
for no_keyword in \
  'Closes' 'Closes #' 'Closes #x' 'See #1' 'discloses #1' 'prefix #1'; do
  rule deny "gh pr create --title \"feat: x\" --body \"$no_keyword\"" 'closing keyword'
done

# --fill takes the body from the commits, where the keyword can't be checked.
rule deny 'gh pr create --fill' '--body'
rule deny 'gh pr create -f' '--body'
rule deny 'gh pr create --fill-first' '--body'
rule deny 'gh pr create --fill-verbose' '--body'
rule deny 'gh pr create --title "feat: x" --fill' '--body'

# gh pr edit checks what's there.
rule none 'gh pr edit 1 --add-label bug'
rule none 'gh pr edit 1 --title "feat: x"'
rule none 'gh pr edit 1 --body "Closes #1"'
rule deny 'gh pr edit 1 --title "add stuff"' 'title'
rule deny 'gh pr edit 1 -t "add stuff"' 'title'
rule deny 'gh pr edit 1 --body "no keyword"' 'closing keyword'
rule deny 'gh pr edit 1 --title "feat: x" --body "no keyword"' 'closing keyword'
rule deny 'gh pr edit 1 --body "Closes #1

Generated with Claude Code"' 'attribution'
rule deny 'gh pr edit 1 --title "Generated with Claude Code"' 'attribution'

# --- Attribution

for line in \
  'Generated with Claude Code' \
  'Co-Authored-By: Claude <noreply@anthropic.com>' \
  '**Co-Authored-By:** Claude' \
  '**Co-Authored-By:** Claude <noreply@anthropic.com>' \
  'Assisted-by: Claude'; do
  rule deny "gh pr comment 1 --body \"Why.

$line\"" 'attribution'
done

for command in \
  'gh pr create --title "feat: x" --body' \
  'gh pr edit 1 --body' \
  'gh pr comment 1 -b' \
  'gh issue create --title x --body' \
  'gh issue edit 1 --body' \
  'gh issue comment 1 --body' \
  'gh release create v1 --notes' \
  'gh release create v1 -n' \
  'gh release edit v1 --notes'; do
  rule deny "$command \"Closes #1

Assisted-by: Claude\"" 'attribution'
done

rule deny 'gh issue create --title x --body "Generated with Claude Code"' 'attribution'
rule deny 'gh issue create --title "Generated with Claude Code" --body x' 'attribution'
rule deny 'gh issue edit 1 --title "Generated with Claude Code"' 'attribution'
rule deny 'gh release create v1 --title "Generated with Claude Code"' 'attribution'
rule deny 'gh release edit v1 -t "Generated with Claude Code"' 'attribution'
rule deny 'gh pr comment 1 --body "Closes #1\n\nAssisted-by: Claude"' 'attribution'
rule deny 'gh pr comment 1 --body=$'"'"'x\n\nCo-Authored-By: Claude'"'" 'attribution'

# Ordinary mentions pass, and these commands don't need a title or a keyword.
rule none 'gh pr comment 1 --body "The hook reads the Claude Code input."'
rule none 'gh pr comment 1 --body "The **Co-Authored-By:** form is rejected."'
rule none 'gh pr comment 1 --body "**Co-Authored-By:** Ana Ruiz"'
rule none 'gh issue create --title x --body "Clean text about Claude."'
rule none 'gh issue edit 1 --add-label bug'
rule none 'gh issue comment 1 --body "Assisted by a person."'
rule none 'gh release create v1 --title "v1" --notes "Clean"'
rule none 'gh release create v1 --generate-notes'
rule none 'gh release edit v1 --draft=false'
rule none 'gh pr view 1 --json body'
rule none 'gh pr list | grep "Generated with Claude Code"'
rule none 'gh pr comment --help'
rule none 'gh pr create --help'

# A heredoc in the body: the text between its lines is what counts.
rule_stdin none <<'COMMAND'
gh pr create --title "feat: x" --body "$(cat <<'EOF'
It's a body with "quotes" and an unmatched ( parenthesis.

Closes #1
EOF
)"
COMMAND

rule_stdin deny 'attribution' <<'COMMAND'
gh pr create --title "feat: x" --body "$(cat <<'EOF'
It's a body.

Closes #1

**Co-Authored-By:** Claude
EOF
)"
COMMAND

rule_stdin deny 'closing keyword' <<'COMMAND'
gh pr create --title "feat: x" --body "$(cat <<'EOF'
It's a body.
EOF
)"
COMMAND

# A plain heredoc appears in no simple command, so it comes from the raw text.
rule_stdin deny 'attribution' <<'COMMAND'
gh pr comment 1 --body-file - <<'EOF'
Text.

Generated with Claude Code
EOF
COMMAND

rule_stdin none <<'COMMAND'
gh pr create --title "feat: x" --body-file - <<'EOF'
Text.

Closes #1
EOF
COMMAND

rule_stdin deny 'closing keyword' <<'COMMAND'
gh pr create --title "feat: x" -F - <<'EOF'
Text.
EOF
COMMAND

# A variable holding the text is in the raw command too.
rule_stdin deny 'attribution' <<'COMMAND'
BODY='Text.

Co-Authored-By: Claude'
gh pr comment 1 --body "$BODY"
COMMAND

# Standard input the hook can't see.
rule deny 'cat b.md | gh pr comment 1 --body-file -' 'read'
rule deny 'cat b.md | gh pr create --title "feat: x" -F -' 'read'

# The same text that isn't going anywhere is no business of this rule.
rule none 'git log --grep="Generated with Claude Code"'
rule none 'gh pr view 1
grep "Generated with Claude Code" notes.md'

# --- Body files

printf 'Why.\n\nCloses #1\n' >"$repo/clean.md"
printf 'Closes #1\n\nGenerated with Claude Code\n' >"$repo/attributed.md"
printf 'Generated with Claude Code\n' >"$repo/only-attributed.md"
printf 'Closes #1\n\n**Co-Authored-By:** Claude\n' >"$repo/marked.md"
printf 'Why.\n' >"$repo/no-keyword.md"
printf 'Closes #1\n' >"$repo/name with space.md"
printf 'Closes #1\n' >"$repo/sub/clean.md"
outside="$(tmp_dir)/outside.md"
printf 'Closes #1\n' >"$outside"

rule none 'gh pr create --title "feat: x" --body-file clean.md'
rule none 'gh pr create --title "feat: x" -F clean.md'
rule none 'gh pr create --title "feat: x" -Fclean.md'
rule none 'gh pr create --title "feat: x" --body-file=clean.md'
rule none 'gh pr create --title "feat: x" --body-file "name with space.md"'
rule none "gh pr create --title \"feat: x\" --body-file \"$outside\""
real_home=$HOME
HOME=$repo
rule none 'gh pr create --title "feat: x" --body-file ~/clean.md'
HOME=$real_home
rule deny 'gh pr create --title "feat: x" --body-file attributed.md' 'attribution'
rule deny 'gh pr create --title "feat: x" --body-file only-attributed.md' 'attribution'
rule deny 'gh pr create --title "feat: x" -F marked.md' 'attribution'
rule deny 'gh pr create --title "feat: x" --body-file no-keyword.md' 'closing keyword'
rule deny 'gh pr edit 1 --body-file no-keyword.md' 'closing keyword'
rule deny 'gh pr edit 1 --body-file attributed.md' 'attribution'
rule deny 'gh pr comment 1 --body-file attributed.md' 'attribution'
rule deny 'gh issue create --title x -F attributed.md' 'attribution'
rule deny 'gh issue edit 1 -F attributed.md' 'attribution'
rule deny 'gh issue comment 1 -F attributed.md' 'attribution'
rule deny 'gh release create v1 --notes-file attributed.md' 'attribution'
rule deny 'gh release create v1 -F attributed.md' 'attribution'
rule deny 'gh release edit v1 --notes-file attributed.md' 'attribution'
rule none 'gh pr comment 1 --body-file no-keyword.md'
rule none 'gh release create v1 --notes-file no-keyword.md'

# A file that can't be read can't be checked.
for unreadable in gone.md sub '$(mktemp)' '<(echo x)' /dev/stdin; do
  rule deny "gh pr comment 1 --body-file $unreadable" 'read'
  rule deny "gh pr create --title \"feat: x\" --body-file $unreadable" 'read'
done

# A relative name is from where the session's shell is.
cd "$repo/sub" || exit 1
rule none 'gh pr create --title "feat: x" --body-file clean.md'
rule deny 'gh pr create --title "feat: x" --body-file attributed.md' 'read'
cd "$repo" || exit 1

# Without a usable cwd in the input, from the project's root.
no_cwd=$(jq -n '{tool_name: "Bash", tool_input: {command: "gh pr comment 1 --body-file attributed.md"}}')
assert_decision deny "$hook" "$no_cwd"
assert_contains "$(reason_of "$hook" "$no_cwd")" 'attribution'

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
