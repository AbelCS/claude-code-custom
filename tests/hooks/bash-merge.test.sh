#!/bin/sh
# shellcheck disable=SC2016 # Dollars and backticks in quotes are commands for the hook.
#
# Tests the Bash rules on local merges into the default branch: which branch and folder a
# command acts on, and what moves them.

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
# shellcheck source=tests/lib/assert.sh
. "$ROOT/tests/lib/assert.sh"
# shellcheck source=tests/lib/hook.sh
. "$ROOT/tests/lib/hook.sh"
# shellcheck source=tests/lib/bash-rules.sh
. "$ROOT/tests/lib/bash-rules.sh"

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

# A -- with nothing after it names no paths, so this moves.
on_branch feat/1-x
rule deny 'git checkout main -- && git merge feat/2-y' 'main'
rule deny 'git checkout not-a-branch -- && git merge feat/2-y' 'separately'
rule deny 'git checkout sub -- && git merge feat/2-y' 'separately'
rule none 'git checkout main -- file && git merge main'
rule none 'git checkout -- && git merge main'
on_branch main
rule none 'git checkout feat/1-x -- && git merge main'
rule deny 'git checkout -- && git merge feat/1-x' 'main'
rule deny 'git checkout feat/1-x -- file && git merge feat/1-x' 'main'
on_branch feat/1-x

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
rule deny 'git -C path merge main' 'separately'
rule deny 'git -C "$MAIN" merge feat/1-x' 'separately'
rule none 'git -C sub merge main'
rule none "git -C \"$other\" merge --abort"
git -C "$other" symbolic-ref HEAD refs/heads/feat/9-z
rule none "git -C \"$other\" merge main"
on_branch main
rule none "git -C \"$other\" merge main"
rule deny 'git -C path merge x' 'separately'
rule deny 'git -C "$MAIN" merge feat/1-x' 'separately'
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

# --- cd moves where the rest of the command acts

# The project on main, the session in a worktree on a work branch.
on_branch main
cd "$worktree" || exit 1
rule deny "cd \"$repo\" && git merge feat/1-x" 'main'
rule deny "cd \"$repo\"; git merge feat/1-x" 'main'
rule deny "(cd \"$repo\"; git merge feat/1-x)" 'main'
rule deny "(cd \"$repo\" && git merge feat/1-x)" 'main'
rule deny "cd -P \"$repo\" && git merge feat/1-x" 'main'
rule deny "cd -- \"$repo\" && git merge feat/1-x" 'main'
rule deny "cd \"$repo\">/dev/null && git merge feat/1-x" 'main'
rule deny "cd \"$repo\" && cd sub && git merge feat/1-x" 'main'
rule deny "cd \"$repo/sub\" && cd .. && git merge feat/1-x" 'main'
rule deny "cd \"$repo\" && git -C sub merge feat/1-x" 'main'
rule none 'git merge main'
rule none "cd \"$repo\" && git switch feat/1-x && git merge main"
rule none "cd \"$repo\"; git switch main; cd \"$worktree\"; git merge main"
rule none "cd \"$repo\" && git merge --abort"
rule none "cd \"$repo\" && git status"
cd "$worktree/sub" || exit 1
rule none 'cd .. && git merge main'
rule deny "cd .. && cd \"$repo\" && git merge feat/1-x" 'main'
cd "$repo" || exit 1

# The session on main, moving to a work branch's worktree.
rule none "cd \"$worktree\" && git merge main"
rule none "cd \"$worktree/sub\" && git merge main"
rule none "(cd \"$worktree\"; git merge main)"
rule none "cd \"$worktree\" && git -C sub merge main"
rule deny "cd \"$worktree\" && cd \"$repo\" && git merge feat/1-x" 'main'
rule deny "cd \"$worktree\" && git -C \"$repo\" merge feat/1-x" 'main'
rule deny "cd \"$worktree\" && git switch main && git merge feat/1-x" 'main'

# A folder that can't be told. The branch makes no difference to these.
for move in \
  'cd "$X"' \
  'cd $X' \
  'cd "$X/sub"' \
  'cd -' \
  'cd "$(git rev-parse --show-toplevel)"' \
  'cd ~someone' \
  'cd no-such-folder'; do
  rule deny "$move && git merge feat/2-y" 'separately'
done
rule deny 'cd "$X" && cd sub && git merge feat/2-y' 'separately'
rule deny 'git -C no-such-folder merge feat/2-y' 'separately'
rule deny 'cd "$X" && git -C sub merge feat/2-y' 'separately'
# Where it might have moved a branch that's judged later.
rule deny "cd \"\$X\" && git switch main; cd \"$worktree\"; git merge main" 'separately'
rule deny 'git -C "$X" switch main && git merge main' 'separately'
# What isn't a merge, or a real merge somewhere known again.
rule none 'cd "$X"'
rule none 'cd "$X" && git status'
rule none 'cd "$X" && git merge --abort'
rule none 'cd "$X" && git merge --ff-only origin/main'
rule none 'cd "$X" && git pull --ff-only'
rule none 'git -C "$X" merge --abort'
rule none "cd \"\$X\" && cd \"$worktree\" && git merge main"
rule none "cd \"\$X\" && git -C \"$worktree\" merge main"
on_branch feat/1-x
rule deny 'cd "$X" && git merge feat/2-y' 'separately'
rule none 'cd "$X" && git pull --ff-only'

# cd with no folder is home, which can be told.
on_branch main
real_home=$HOME
HOME=$repo
rule deny 'cd && git merge feat/1-x' 'main'
rule deny 'cd ~ && git merge feat/1-x' 'main'
rule deny 'cd ~/sub && git merge feat/1-x' 'main'
cd "$worktree" || exit 1
rule deny 'cd && git merge feat/1-x' 'main'
cd "$repo" || exit 1
HOME=$worktree
rule none 'cd && git merge main'
rule none 'cd ~/sub && git merge main'
HOME=
rule deny 'cd && git merge main' 'separately'
HOME=$real_home
on_branch feat/1-x

# --- What landing and updating use stays clean, wherever the session is

landing='gh pr merge 7 --squash --subject "chore: x (#2)" --body "" --delete-branch'
clean_everywhere() {
  rule none "$landing"
  rule none 'git pull --ff-only'
}
git -C "$repo" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
for branch in main feat/1-x feat/2-y trunk; do
  on_branch "$branch"
  clean_everywhere
done
git -C "$repo" switch -q --detach main
clean_everywhere
on_branch main
cd "$worktree" || exit 1
clean_everywhere
cd "$repo" || exit 1
git -C "$repo" symbolic-ref --delete refs/remotes/origin/HEAD
on_branch feat/1-x
