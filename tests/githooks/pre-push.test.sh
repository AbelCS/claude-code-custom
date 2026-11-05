#!/bin/sh
# Tests the pre-push template, installed in a temp repo the way setup installs it. Some
# tests feed it the stdin git documents, for lines a real push can't easily make. The
# rest are real pushes to a bare remote, so git decides what the hook sees.

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
# shellcheck source=tests/lib/assert.sh
. "$ROOT/tests/lib/assert.sh"

templates="$ROOT/plugins/dev-workflow/skills/setup/templates/githooks"

# The owner's own git settings must not change a result.
GIT_CONFIG_GLOBAL=/dev/null
GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL GIT_CONFIG_NOSYSTEM

# --- The template

# Git silently skips a hook that isn't executable.
assert_exit 0 test -x "$templates/pre-push"
assert_exit 1 grep -Ewq 'jq|node|python3?' "$templates/pre-push"

# --- The fixture: a path with a space, because git passes hooks that path

scratch=$(tmp_dir)
CHECK_LOG="$scratch/check.log"
CHECK_EXIT=0
export CHECK_LOG CHECK_EXIT

write_env() { # <default branch> <check command>
  cat >"$hooks/dev-workflow.env" <<ENV
DW_DEFAULT_BRANCH='$1'
DW_CHECK='$2'
DW_CI_ALLOWLIST=''
DW_FORMATTERS=''
ENV
}

# Sets $repo, $hooks and $remote to a new repo with one commit on main, and an empty
# bare remote named origin. Nothing the fixture needs shows as an uncommitted change.
new_fixture() {
  parent="$(tmp_dir)/a b"
  repo="$parent/repo"
  remote="$parent/remote.git"
  hooks="$repo/.githooks"
  new_repo "$repo"
  git init -q --bare -b main "$remote"
  git -C "$repo" remote add origin "$remote"
  mkdir -p "$hooks" "$repo/scripts"
  cp "$templates/pre-push" "$templates/dw-lib.sh" "$hooks/"
  git -C "$repo" config core.hooksPath .githooks
  printf '.githooks\nscripts\n' >>"$repo/.git/info/exclude"
  write_env main scripts/check
  # Logs a run with its arguments, its folder and the git variables that would point its
  # git commands at this repo, and prints a line that must reach the user.
  cat >"$repo/scripts/check" <<'STUB'
#!/bin/sh
printf 'ran[%s] in %s\n' "$*" "$(pwd -P)" >>"$CHECK_LOG"
printf 'git[%s|%s|%s]\n' "${GIT_DIR-unset}" "${GIT_WORK_TREE-unset}" "${GIT_INDEX_FILE-unset}" >>"$CHECK_LOG"
echo 'output of the check'
exit "$CHECK_EXIT"
STUB
  chmod +x "$repo/scripts/check"
  new_commit
}

new_commit() {
  git -C "$repo" commit -q --allow-empty -m 'chore: a commit'
}

sha_of() { # <revision>
  git -C "$repo" rev-parse "$1"
}

remote_sha() { # <ref>: prints nothing if the remote doesn't have it.
  git -C "$remote" rev-parse -q --verify "$1"
}

push() { # <git push arguments...>
  git -C "$repo" push -q origin "$@" 2>&1
}

# A real push that the hook lets through.
pushes() { # <git push arguments...>
  assert_exit 0 push "$@"
}

# A real push that the hook stops, printing the text, and that leaves the remote alone.
# The "pre-push: " shows that the verdict was the hook's, and not git's own.
refuses() { # <text the hook must print> <git push arguments...>
  refused_text=$1
  shift
  refused_before=$(git -C "$remote" for-each-ref)
  assert_exit 1 push "$@"
  refused_output=$(push "$@")
  assert_contains "$refused_output" 'pre-push: '
  assert_contains "$refused_output" "$refused_text"
  assert_exit 0 test "$(git -C "$remote" for-each-ref)" = "$refused_before"
}

# Runs the hook as git does, from the top of the work tree, on these stdin lines.
feed_to() { # <remote url> <stdin lines>
  (cd "$repo" && printf '%s\n' "$2" | "$hooks/pre-push" origin "$1")
}

feed() { # <stdin lines>
  feed_to "$remote" "$1"
}

feed_nothing() { # What git sends when everything is up to date.
  (cd "$repo" && "$hooks/pre-push" origin "$remote" </dev/null)
}

feed_output() { # <stdin lines>
  feed "$1" 2>&1
}

zero=0000000000000000000000000000000000000000
zero_sha256=0000000000000000000000000000000000000000000000000000000000000000

line_for() { # <branch> <remote branch>: a push of the branch, new on the remote.
  printf 'refs/heads/%s %s refs/heads/%s %s' "$1" "$(sha_of "refs/heads/$1")" "$2" "$zero"
}

check_ran() {
  assert_contains "$(cat "$CHECK_LOG")" 'ran['
}

check_did_not_run() {
  assert_exit 0 test ! -s "$CHECK_LOG"
}

forget_runs() {
  : >"$CHECK_LOG"
}

# --- Fed the documented stdin: a branch, with the check passing or failing

new_fixture
git -C "$repo" switch -q -c feat/1-x
# The remote needs a branch of its own, or this is a new repo's first push.
git -C "$repo" push -q --no-verify origin main

forget_runs
assert_exit 0 feed "$(line_for feat/1-x feat/1-x)"
check_ran

forget_runs
CHECK_EXIT=1
assert_exit 1 feed "$(line_for feat/1-x feat/1-x)"
check_ran
failed=$(feed_output "$(line_for feat/1-x feat/1-x)")
assert_contains "$failed" 'pre-push: '
assert_contains "$failed" 'scripts/check'
assert_contains "$failed" 'output of the check'
# Stdout is the hook's interface with git, so the check's output goes to stderr.
assert_exit 0 test -z "$(feed "$(line_for feat/1-x feat/1-x)" 2>/dev/null)"
CHECK_EXIT=0

# Any exit that isn't 0 is a failure, and the hook says exit 1 for all of them.
write_env main 'exit 3'
assert_exit 1 feed "$(line_for feat/1-x feat/1-x)"

# The setting is a command line, not only a path.
write_env main 'scripts/check --fast'
forget_runs
assert_exit 0 feed "$(line_for feat/1-x feat/1-x)"
assert_contains "$(cat "$CHECK_LOG")" 'ran[--fast]'

# --- No check configured

write_env main ''
forget_runs
assert_exit 1 feed "$(line_for feat/1-x feat/1-x)"
assert_contains "$(feed_output "$(line_for feat/1-x feat/1-x)")" 'no check command is configured'
check_did_not_run

# A deletion runs nothing, so it doesn't need one.
assert_exit 0 feed "(delete) $zero refs/heads/old $(sha_of main)"
write_env main scripts/check

# --- Fed: the default branch

forget_runs
assert_exit 1 feed "$(line_for feat/1-x main)"
assert_contains "$(feed_output "$(line_for feat/1-x main)")" 'directly to main'
check_did_not_run

# One forbidden ref rejects the batch, wherever it comes in the list.
git -C "$repo" switch -q main
git -C "$repo" branch -f feat/1-x main
batch="$(line_for feat/1-x feat/1-x)
$(line_for main main)"
assert_exit 1 feed "$batch"
assert_contains "$(feed_output "$batch")" 'directly to main'
check_did_not_run
batch="$(line_for main main)
$(line_for feat/1-x feat/1-x)"
assert_exit 1 feed "$batch"
check_did_not_run

# Only the configured branch is protected.
write_env trunk scripts/check
assert_exit 0 feed "$(line_for main main)"
assert_exit 1 feed "$(line_for main trunk)"
assert_contains "$(feed_output "$(line_for main trunk)")" 'directly to trunk'
write_env main scripts/check

# A remote it can't read can't show that this is a first push.
assert_exit 1 feed_to "$parent/no-such-remote" "$(line_for main main)"

# --- Fed: a new repo's first push

new_fixture
forget_runs
assert_exit 0 feed "$(line_for main main)"
check_ran
# And the check still decides it.
CHECK_EXIT=1
assert_exit 1 feed "$(line_for main main)"
CHECK_EXIT=0

# --- Fed: deletions

new_fixture
git -C "$repo" push -q --no-verify origin main
forget_runs
assert_exit 0 feed "(delete) $zero refs/heads/old $(sha_of main)"
check_did_not_run

# In either hash format.
assert_exit 0 feed "(delete) $zero_sha256 refs/heads/old $zero_sha256"
check_did_not_run

# A deletion doesn't excuse what comes with it.
batch="(delete) $zero refs/heads/old $(sha_of main)
$(line_for main other)"
assert_exit 0 feed "$batch"
check_ran

forget_runs
assert_exit 0 feed_nothing
check_did_not_run

# --- Fed: what doesn't parse doesn't pass

forget_runs
assert_exit 1 feed 'garbage'
check_did_not_run
assert_exit 1 feed "refs/heads/main notasha refs/heads/other $zero"
check_did_not_run

# --- Real pushes: a new repo's first push may go to main, and it still runs the check

new_fixture
forget_runs
pushes main
assert_exit 0 test "$(remote_sha refs/heads/main)" = "$(sha_of main)"
check_ran
# The check's folder is the hook's to get right: DW_CHECK is relative to the top.
assert_contains "$(cat "$CHECK_LOG")" "in $(cd "$repo" && pwd -P)"

# After that, a direct push to main is rejected before the check runs.
new_commit
forget_runs
refuses 'directly to main' main
check_did_not_run

# Going through another local branch name doesn't get around it.
git -C "$repo" switch -q -c chore/2-thing
refuses 'directly to main' chore/2-thing:main
check_did_not_run

# Neither does deleting it.
refuses 'directly to main' :main
check_did_not_run

# One forbidden ref rejects the whole push.
refuses 'directly to main' chore/2-thing main
assert_exit 1 test -n "$(remote_sha refs/heads/chore/2-thing)"
check_did_not_run

# --- Real pushes: other branches

# They push when the check passes.
forget_runs
pushes chore/2-thing
assert_exit 0 test "$(remote_sha refs/heads/chore/2-thing)" = "$(sha_of chore/2-thing)"
check_ran

# A failing check stops the push.
new_commit
forget_runs
CHECK_EXIT=1
refuses 'scripts/check' chore/2-thing
assert_contains "$(push chore/2-thing)" 'output of the check'
CHECK_EXIT=0

# So does a missing check.
mv "$repo/scripts/check" "$repo/scripts/check.away"
refuses 'scripts/check' chore/2-thing
mv "$repo/scripts/check.away" "$repo/scripts/check"

# A branch that's already up to date has nothing to check.
pushes chore/2-thing
forget_runs
pushes chore/2-thing
check_did_not_run

# Deleting a branch doesn't run the check, even from another branch.
git -C "$repo" push -q --no-verify origin chore/2-thing:chore/3-old
forget_runs
pushes :chore/3-old
assert_exit 1 test -n "$(remote_sha refs/heads/chore/3-old)"
check_did_not_run

# A new main on a remote that already has branches isn't a new repo's first push.
other_remote="$(tmp_dir)/other.git"
git init -q --bare -b main "$other_remote"
git -C "$repo" remote add other "$other_remote"
assert_exit 0 git -C "$repo" push -q other chore/2-thing
git -C "$repo" branch -f main chore/2-thing
assert_exit 1 git -C "$repo" push -q other main
assert_exit 1 test -n "$(git -C "$other_remote" rev-parse -q --verify refs/heads/main)"

# --- Real pushes: the check runs on the checkout, so it has to be what's being pushed

new_fixture
git -C "$repo" push -q --no-verify origin main
git -C "$repo" switch -q -c feature
new_commit
git -C "$repo" switch -q main

# From a clean main, this would check main and publish feature untested.
forget_runs
refuses 'git switch feature' feature
check_did_not_run
assert_exit 1 test -n "$(remote_sha refs/heads/feature)"

# Pushing the branch you're on stays allowed, under any name on the remote.
git -C "$repo" switch -q feature
forget_runs
pushes feature
check_ran
new_commit
pushes feature:refs/heads/feature-copy
pushes HEAD:refs/heads/feature-head

# A detached HEAD holds the same code as the branch it's on.
new_commit
git -C "$repo" switch -q --detach feature
pushes feature
git -C "$repo" switch -q feature

# Another revision isn't what's checked out, and neither is an expression's. The fix
# has to work with no branch to name.
refuses 'git switch --detach' 'HEAD~1:refs/heads/older'
assert_contains "$(push 'HEAD~1:refs/heads/older')" "$(sha_of 'HEAD~1')"

# One wrong ref rejects a batch of right ones.
git -C "$repo" branch stale 'HEAD~1'
refuses 'git switch stale' feature stale

# The local ref git reports can hold a space, which must not shift the other fields.
new_commit
forget_runs
pushes 'HEAD@{0 minutes ago}:refs/heads/spaced'
check_ran
assert_exit 0 test "$(remote_sha refs/heads/spaced)" = "$(sha_of HEAD)"

# Deletions don't count: they publish nothing, from any checkout.
git -C "$repo" push -q --no-verify origin feature:refs/heads/to-delete
git -C "$repo" switch -q main
forget_runs
pushes :to-delete
check_did_not_run

# A deletion with the branch you're on checks that branch.
git -C "$repo" push -q --no-verify origin feature:refs/heads/to-delete
git -C "$repo" switch -q feature
forget_runs
pushes feature :to-delete
check_ran
assert_exit 1 test -n "$(remote_sha refs/heads/to-delete)"

# --- Real pushes: tags

# A tag on what's checked out, light or annotated, whose name differs from the commit's.
forget_runs
git -C "$repo" tag v1-light
pushes v1-light
check_ran
git -C "$repo" tag -a v1-annotated -m 'a tag'
assert_exit 1 test "$(sha_of v1-annotated)" = "$(sha_of HEAD)"
forget_runs
pushes v1-annotated
check_ran

# A tag on anything else would be published unchecked, whichever kind it is.
git -C "$repo" tag v0-light 'HEAD~1'
git -C "$repo" tag -a v0-annotated -m 'a tag' 'HEAD~1'
forget_runs
refuses 'git switch --detach' v0-light
refuses 'git switch --detach' v0-annotated
check_did_not_run

# Following the fix makes it pass.
git -C "$repo" switch -q --detach "$(sha_of v0-annotated)"
pushes v0-annotated
git -C "$repo" switch -q feature

# Older refs in one push, as from --tags or --follow-tags, have no checkout that matches
# them all, so switching isn't enough: each has to go on its own.
git -C "$repo" tag v-older-1 'HEAD~1'
git -C "$repo" tag v-older-2 'HEAD~2'
refuses 'on its own' v-older-1 v-older-2
assert_contains "$refused_output" 'refs/tags/v-older-1 would get'
assert_contains "$refused_output" 'refs/tags/v-older-2 would get'
assert_exit 0 test "$(printf '%s\n' "$refused_output" | grep -c 'on its own')" = 2
git -C "$repo" switch -q --detach v-older-1
pushes v-older-1
git -C "$repo" switch -q --detach v-older-2
pushes v-older-2
git -C "$repo" switch -q feature

# --- Real pushes: notes hold no code, so the check has nothing to say about them

git -C "$repo" notes add -m 'a note' 'HEAD~1'
forget_runs
pushes refs/notes/commits
check_did_not_run
assert_exit 0 test "$(remote_sha refs/notes/commits)" = "$(sha_of refs/notes/commits)"

# Where a ref lands decides that, not where it came from: on a branch, it's code.
refuses 'git switch --detach' refs/notes/commits:refs/heads/from-notes
pushes 'HEAD~1:refs/notes/from-code'
check_did_not_run

# Notes don't excuse what comes with them.
new_commit
git -C "$repo" notes add -m 'another note' HEAD
forget_runs
pushes refs/notes/commits feature
check_ran
assert_exit 0 test "$(remote_sha refs/notes/commits)" = "$(sha_of refs/notes/commits)"

# --- Real pushes: a dirty work tree warns, because the check saw what isn't pushed

new_fixture
git -C "$repo" push -q --no-verify origin main
git -C "$repo" switch -q -c feature
printf 'one\n' >"$repo/tracked.txt"
git -C "$repo" add tracked.txt
git -C "$repo" commit -q -m 'chore: a file'

warning='the check ran on uncommitted changes'

clean_output=$(push feature)
assert_not_contains "$clean_output" 'warning'

new_commit
printf 'two\n' >"$repo/tracked.txt"
forget_runs
modified_output=$(push feature)
assert_exit 0 test "$(remote_sha refs/heads/feature)" = "$(sha_of feature)"
assert_contains "$modified_output" 'pre-push: warning'
assert_contains "$modified_output" "$warning"
check_ran

new_commit
git -C "$repo" add tracked.txt
staged_output=$(push feature)
assert_exit 0 test "$(remote_sha refs/heads/feature)" = "$(sha_of feature)"
assert_contains "$staged_output" "$warning"
git -C "$repo" commit -q -m 'chore: a change'

# A new file can change what a check does too, whatever the status settings hide.
new_commit
printf 'new\n' >"$repo/untracked.txt"
git -C "$repo" config status.showUntrackedFiles no
untracked_output=$(push feature)
assert_exit 0 test "$(remote_sha refs/heads/feature)" = "$(sha_of feature)"
assert_contains "$untracked_output" "$warning"
git -C "$repo" config --unset status.showUntrackedFiles

# It warns when the check fails too, because that may be why, and the failure stands.
new_commit
CHECK_EXIT=1
failing_output=$(push feature)
CHECK_EXIT=0
assert_contains "$failing_output" "$warning"
assert_contains "$failing_output" 'the check failed'
assert_exit 1 test "$(remote_sha refs/heads/feature)" = "$(sha_of feature)"
rm "$repo/untracked.txt"

# A deletion runs no check, so there's nothing to warn about.
printf 'new\n' >"$repo/untracked.txt"
git -C "$repo" push -q --no-verify origin feature:refs/heads/to-delete
assert_not_contains "$(push :to-delete)" 'warning'
rm "$repo/untracked.txt"

# A check that leaves files behind doesn't make it warn: only what it started on counts.
cat >"$repo/scripts/check" <<'STUB'
#!/bin/sh
: >leftover.txt
STUB
new_commit
assert_not_contains "$(push feature)" 'warning'
rm "$repo/leftover.txt"

# --- Where it runs from: a subfolder, and a linked worktree whose .git is a file

new_fixture
git -C "$repo" push -q --no-verify origin main
git -C "$repo" switch -q -c feature
mkdir "$repo/sub"
forget_runs
assert_exit 0 git -C "$repo/sub" push -q origin feature
check_ran
assert_contains "$(cat "$CHECK_LOG")" "in $(cd "$repo" && pwd -P)"

worktree="$parent/linked tree"
git -C "$repo" worktree add -q -b wt-branch "$worktree" feature
assert_exit 0 test -f "$worktree/.git"
cp -R "$hooks" "$worktree/.githooks"
cp -R "$repo/scripts" "$worktree/scripts"
git -C "$worktree" commit -q --allow-empty -m 'chore: a commit'
forget_runs
assert_exit 0 git -C "$worktree" push -q origin wt-branch
check_ran
assert_contains "$(cat "$CHECK_LOG")" "in $(cd "$worktree" && pwd -P)"
assert_exit 0 test "$(remote_sha refs/heads/wt-branch)" = "$(git -C "$worktree" rev-parse HEAD)"
# Git sets GIT_DIR for a hook here. Passed on, a check's git commands in a temp fixture
# would act on the real repo.
assert_contains "$(cat "$CHECK_LOG")" 'git[unset|unset|unset]'

# The same goes for the others, which git passes on when the caller sets them.
git -C "$worktree" commit -q --allow-empty -m 'chore: a commit'
worktree_index="$(git -C "$worktree" rev-parse --absolute-git-dir)/index"
forget_runs
assert_exit 0 env GIT_WORK_TREE="$worktree" GIT_INDEX_FILE="$worktree_index" \
  git -C "$worktree" push -q origin wt-branch
assert_contains "$(cat "$CHECK_LOG")" 'git[unset|unset|unset]'

# The main checkout isn't on that branch: each work tree's own HEAD is the one that counts.
git -C "$worktree" commit -q --allow-empty -m 'chore: a commit'
# Git won't switch to a branch that another worktree has, so the message offers that too.
refuses 'git switch wt-branch, or push from the worktree that has it' wt-branch

# --- The env file: nothing here can run without knowing the rules

new_fixture
git -C "$repo" push -q --no-verify origin main

env_refuses() { # <text the hook must print>
  forget_runs
  assert_exit 1 feed "$(line_for main other)"
  env_output=$(feed_output "$(line_for main other)")
  assert_contains "$env_output" 'pre-push: '
  assert_contains "$env_output" "$1"
  check_did_not_run
}

rm "$hooks/dev-workflow.env"
env_refuses 'dev-workflow.env'

printf "DW_CHECK='unterminated\n" >"$hooks/dev-workflow.env"
env_refuses 'dev-workflow.env'

# Both settings are there, but something in the file failed, so they can't be trusted.
printf "DW_DEFAULT_BRANCH='main'\nDW_CHECK='scripts/check'\nfalse\n" >"$hooks/dev-workflow.env"
env_refuses 'dev-workflow.env'

# A setting left out isn't the same as one left empty, and the caller's isn't the project's.
export DW_DEFAULT_BRANCH=main DW_CHECK=scripts/check
printf "DW_DEFAULT_BRANCH='main'\n" >"$hooks/dev-workflow.env"
env_refuses 'dev-workflow.env'
printf "DW_CHECK='scripts/check'\n" >"$hooks/dev-workflow.env"
env_refuses 'dev-workflow.env'
printf "DW_DEFAULT_BRANCH=''\nDW_CHECK='scripts/check'\n" >"$hooks/dev-workflow.env"
env_refuses 'dev-workflow.env'
unset DW_DEFAULT_BRANCH DW_CHECK

write_env main scripts/check
assert_exit 0 feed "$(line_for main other)"

# A missing library can't check anything either.
rm "$hooks/dw-lib.sh"
env_refuses 'dw-lib.sh is missing'
