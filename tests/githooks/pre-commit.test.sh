#!/bin/sh
# Tests the pre-commit template, installed in a temp repo the way setup installs it
# and run by real commits, so git decides what the hook sees.

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
assert_exit 0 test -x "$templates/pre-commit"
assert_exit 1 grep -Ewq 'jq|node|python3?' "$templates/pre-commit"

# --- The fixture: a path with a space, because git passes hooks that path

scratch=$(tmp_dir)
repo="$(tmp_dir)/a b/repo"
new_repo "$repo"
hooks="$repo/.githooks"
mkdir -p "$hooks"
cp "$templates/pre-commit" "$templates/dw-lib.sh" "$hooks/"
git -C "$repo" config core.hooksPath .githooks

# The formatter fails on any file containing BAD, and logs each argument on one line,
# so that a split or merged argument shows. It's named by how it was called.
FMT_LOG="$scratch/formatter log"
export FMT_LOG
cat >"$repo/fmt" <<'FMT'
#!/bin/sh
status=0
for file in "$@"; do
  printf '%s[%s]\n' "$(basename "$0")" "$file" >>"$FMT_LOG"
  case $file in --*) continue ;; esac
  grep -q BAD "$file"
  [ $? -eq 1 ] || status=1
done
exit $status
FMT
chmod +x "$repo/fmt"
cp "$repo/fmt" "$repo/fmt2"

# Nothing the fixture itself needs is ever staged or cleaned away.
printf '.githooks\nfmt\nfmt2\n' >>"$repo/.git/info/exclude"

write_env() { # <formatters> <allowlist>
  cat >"$hooks/dev-workflow.env" <<ENV
DW_DEFAULT_BRANCH='main'
DW_CHECK='scripts/check'
DW_CI_ALLOWLIST='$2'
DW_FORMATTERS='$1'
ENV
}

attempt() {
  git -C "$repo" commit -q -m 'feat: x' "$@"
}

blocks() { # <text the hook must print>...: and it was the hook.
  if blocked=$(attempt 2>&1); then
    _assert_fail "expected the commit to be blocked"
  fi
  assert_contains "$blocked" 'pre-commit: '
  for text in "$@"; do
    assert_contains "$blocked" "$text"
  done
}

stage() { # <path> <content>
  mkdir -p "$(dirname "$repo/$1")"
  printf '%s\n' "$2" >"$repo/$1"
  git -C "$repo" --literal-pathspecs add -- "$1"
}

log_is() { # <expected log>
  log_found=$(cat "$FMT_LOG" 2>/dev/null)
  assert_exit 0 test "$log_found" = "$1"
}

# --- The first commit has no HEAD to compare with

write_env '*.rs|./fmt' ''
stage a.rs 'BAD'
blocks 'a.rs'
stage a.rs 'clean'
assert_exit 0 attempt
base=$(git -C "$repo" rev-parse HEAD)

fresh() { # Back to the first commit, with an empty log.
  git -C "$repo" reset -q --hard "$base" || _assert_fail "could not reset the fixture"
  git -C "$repo" clean -fdq || _assert_fail "could not clean the fixture"
  rm -f "$FMT_LOG"
}

# --- Formatting

fresh
stage b.rs 'BAD'
blocks 'b.rs' './fmt'

fresh
stage b.rs 'clean'
assert_exit 0 attempt
log_is 'fmt[b.rs]'

# A file no formatter claims.
fresh
stage b.ts 'BAD'
assert_exit 0 attempt
log_is ''

# Nothing staged, including for a rule that would match anything.
for rule in '*.rs|./fmt' '*|./fmt'; do
  write_env "$rule" ''
  fresh
  assert_exit 0 attempt --allow-empty
  log_is ''
done

# Each formatter gets its own files, all at once.
write_env '*.rs|./fmt
*.ts|./fmt2' ''
fresh
stage b.rs 'clean'
stage c.ts 'clean'
stage d.rs 'clean'
stage e.md 'BAD'
assert_exit 0 attempt
log_is 'fmt[b.rs]
fmt[d.rs]
fmt2[c.ts]'

# Only the formatter that failed is named, with its files.
fresh
stage b.rs 'clean'
stage c.ts 'BAD'
blocks 'c.ts' './fmt2'
assert_not_contains "$blocked" 'b.rs'

# Both are run, so one commit shows everything to fix.
fresh
stage b.rs 'BAD'
stage c.ts 'BAD'
blocks 'b.rs' 'c.ts'

# A rule can have arguments, which come before the files.
write_env '*.rs|./fmt --check --mode=x' ''
fresh
stage b.rs 'clean'
assert_exit 0 attempt
log_is 'fmt[--check]
fmt[--mode=x]
fmt[b.rs]'

# A formatter that reads stdin can't take the rest of the rules from the hook.
cat >"$repo/fmt-stdin" <<'FMT'
#!/bin/sh
cat >/dev/null
FMT
chmod +x "$repo/fmt-stdin"
printf 'fmt-stdin\n' >>"$repo/.git/info/exclude"
write_env '*.rs|./fmt-stdin
*.rs|./fmt' ''
fresh
stage b.rs 'clean'
stage c.rs 'clean'
assert_exit 0 attempt
log_is 'fmt[b.rs]
fmt[c.rs]'

# File names reach the formatter as they are, as one argument each.
write_env '*.rs|./fmt' ''
accented=$(printf 'caf\303\251.rs')
# shellcheck disable=SC2016 # The dollar is part of the name.
for name in 'a b.rs' 'two  spaces.rs' "$accented" 'quo"te.rs' "apos'trophe.rs" 'back\slash.rs' 'do$lar.rs' 'tab	bed.rs' 'star*.rs'; do
  fresh
  stage "$name" 'clean'
  assert_exit 0 attempt
  log_is "fmt[$name]"
  fresh
  stage "$name" 'BAD'
  blocks "$name"
done

# A name can't pass as one of the formatter's options.
fresh
stage '-b.rs' 'BAD'
blocks '-b.rs'
fresh
stage '-b.rs' 'clean'
assert_exit 0 attempt
log_is 'fmt[./-b.rs]'

# A line break can't survive the hook's file list, so it says so and doesn't guess.
fresh
newline_name='new
line.rs'
stage "$newline_name" 'clean'
blocks 'line break'

# The glob matches at any depth, and the formatter runs from the top of the repo.
fresh
stage 'src/deep/b.rs' 'clean'
assert_exit 0 git -C "$repo/src/deep" commit -q -m 'feat: x'
log_is 'fmt[src/deep/b.rs]'

# Only staged files: another changed file isn't checked.
fresh
printf 'BAD\n' >"$repo/a.rs"
stage b.rs 'clean'
assert_exit 0 attempt
log_is 'fmt[b.rs]'

# What `commit -a` and `commit <path>` will commit counts as staged. Git gives the hook
# another index for these, so a look at the normal one would miss them.
fresh
printf 'BAD\n' >"$repo/a.rs"
assert_exit 1 attempt -a
assert_contains "$(attempt -a 2>&1)" 'a.rs'
assert_exit 1 attempt a.rs
assert_contains "$(attempt a.rs 2>&1)" 'a.rs'

# A deleted file has nothing to format.
fresh
git -C "$repo" rm -q a.rs
assert_exit 0 attempt
log_is ''

# A renamed file is checked under its new name only.
fresh
git -C "$repo" mv a.rs renamed.rs
assert_exit 0 attempt
log_is 'fmt[renamed.rs]'

fresh
git -C "$repo" mv a.rs renamed.rs
printf 'BAD\n' >"$repo/renamed.rs"
git -C "$repo" add renamed.rs
blocks 'renamed.rs'

# A formatter works on the file on disk, which may not be what's staged. So a partly
# staged file blocks, either way round, without asking the formatter about the wrong
# copy, and the hook says what to do.
partly_staged='has unstaged changes'
fresh
stage b.rs 'BAD'
printf 'clean\n' >"$repo/b.rs"
blocks 'b.rs' "$partly_staged" 'stage the whole file' 'git stash --keep-index'
log_is ''

fresh
stage b.rs 'clean'
printf 'BAD\n' >"$repo/b.rs"
blocks 'b.rs' "$partly_staged" 'stage the whole file' 'git stash --keep-index'
log_is ''

fresh
stage b.rs 'clean'
printf 'clean too\n' >"$repo/b.rs"
blocks 'b.rs' "$partly_staged"

# A file staged but gone from disk can't be checked either.
fresh
stage b.rs 'clean'
rm "$repo/b.rs"
blocks 'b.rs' "$partly_staged"
log_is ''

# The other files are still checked.
fresh
stage b.rs 'clean'
printf 'clean too\n' >"$repo/b.rs"
stage c.rs 'BAD'
blocks 'b.rs' "$partly_staged" 'c.rs' './fmt'
log_is 'fmt[c.rs]'

# What the hook suggests works, both ways.
fresh
stage b.rs 'BAD'
printf 'clean\n' >"$repo/b.rs"
git -C "$repo" add b.rs
assert_exit 0 attempt
log_is 'fmt[b.rs]'

fresh
stage b.rs 'BAD'
printf 'clean\n' >"$repo/b.rs"
git -C "$repo" stash push -q --keep-index
blocks 'b.rs' './fmt'
assert_not_contains "$blocked" "$partly_staged"
git -C "$repo" stash drop -q

fresh
stage b.rs 'clean'
printf 'BAD\n' >"$repo/b.rs"
git -C "$repo" stash push -q --keep-index
assert_exit 0 attempt
git -C "$repo" stash drop -q

# Nothing is said when disk and index agree, and `commit -a` makes them agree.
fresh
stage b.rs 'clean'
assert_not_contains "$(attempt 2>&1)" "$partly_staged"
fresh
printf 'clean too\n' >"$repo/a.rs"
assert_exit 0 attempt -a
fresh
printf 'clean too\n' >"$repo/a.rs"
assert_exit 0 attempt a.rs

# Without a formatter rule for the file, unstaged changes are the owner's business,
# and so are ones in a file that isn't being committed.
fresh
stage b.ts 'clean'
printf 'BAD\n' >"$repo/b.ts"
assert_exit 0 attempt
fresh
stage c.rs 'clean'
printf 'BAD\n' >"$repo/a.rs"
assert_exit 0 attempt

# A formatter that can't run blocks: it checked nothing.
write_env '*.rs|./no-such-formatter' ''
fresh
stage b.rs 'clean'
blocks 'b.rs' './no-such-formatter'

# A rule the hook can't read blocks, even for a commit it wouldn't apply to.
for bad_rule in 'no separator' '|./fmt' '*.rs|'; do
  write_env "$bad_rule" ''
  fresh
  stage b.ts 'clean'
  blocks 'DW_FORMATTERS' "$bad_rule"
done

# Blank lines are nothing to worry about.
write_env '
*.rs|./fmt

' ''
fresh
stage b.rs 'clean'
assert_exit 0 attempt
log_is 'fmt[b.rs]'

# --- CI triggers

workflow=.github/workflows/x.yml
allowed=.github/workflows/release.yml
write_env '' "$allowed
.github/workflows/other.yml"

workflow_blocks() { # <trigger> <file content>
  fresh
  stage "$workflow" "$2"
  blocks "$workflow" "has a $1 trigger"
}

workflow_passes() { # <file content>
  fresh
  stage "$workflow" "$1"
  assert_exit 0 attempt
}

jobs='jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - run: echo hi'

# A few real commits for each decision. The shapes the detector reads are in
# ci-triggers.test.sh, against the detector itself.
workflow_blocks push 'on: push'
workflow_blocks pull_request 'on: [workflow_dispatch, pull_request]'
workflow_blocks pull_request_target "on:
  workflow_dispatch:
  pull_request_target:
    types: [opened]
$jobs"
workflow_blocks push "on:
- workflow_dispatch
- push
$jobs"
workflow_passes 'on: workflow_dispatch'
workflow_passes 'name: push
on: workflow_dispatch
jobs:
  push:
    steps:
      - name: push
        run: echo "on: push"'

workflow_unreadable() { # <file content>
  fresh
  stage "$workflow" "$1"
  blocks "$workflow" 'could not read the triggers'
}

workflow_unreadable 'on: *x'
workflow_unreadable '{on: push}'

# It's the staged copy that counts, not the one on disk, either way round.
fresh
stage "$workflow" 'on: push'
printf 'on: workflow_dispatch\n' >"$repo/$workflow"
blocks "$workflow" push
fresh
stage "$workflow" 'on: workflow_dispatch'
printf 'on: push\n' >"$repo/$workflow"
assert_exit 0 attempt

# Both extensions, and only real workflows: GitHub ignores any deeper or elsewhere.
fresh
stage .github/workflows/x.yaml 'on: push'
blocks .github/workflows/x.yaml push
fresh
stage .github/workflows/sub/x.yml 'on: push'
assert_exit 0 attempt

# A workflow name with a space.
fresh
stage '.github/workflows/a b.yml' 'on: push'
blocks '.github/workflows/a b.yml' push

# The allowlist takes exact paths.
fresh
stage "$allowed" 'on: push'
assert_exit 0 attempt
fresh
stage .github/workflows/release.yml.yml 'on: push'
blocks .github/workflows/release.yml.yml push

# Deleting a workflow is fine, and removes the problem.
trigger_base=$base
fresh
stage "$workflow" 'on: workflow_dispatch'
assert_exit 0 attempt
printf 'on: push\n' >"$repo/$workflow"
git -C "$repo" add "$workflow"
git -C "$repo" commit -q --no-verify -m 'feat: push trigger'
base=$(git -C "$repo" rev-parse HEAD)
fresh
git -C "$repo" rm -q "$workflow"
assert_exit 0 attempt

# So is moving it out of the workflows folder, whichever way git is set to see a move.
for renames in true false; do
  fresh
  mkdir -p "$repo/docs"
  git -C "$repo" mv "$workflow" docs/x.yml
  assert_exit 0 git -C "$repo" -c "diff.renames=$renames" commit -q -m 'feat: x'
done

# Only a gained trigger blocks: an edit can keep the ones the file has in HEAD, however
# it writes them or whatever is staged or on disk.
for kept in 'name: edited
on: push' 'on: [push]' 'on: { push: {} }' 'on:
  push:
    branches: [main]' 'on: [push, workflow_dispatch]' 'on: workflow_dispatch'; do
  workflow_passes "$kept"
done

# A new trigger blocks by its own name, beside one that's already there.
workflow_blocks pull_request 'on: [push, pull_request]'
assert_not_contains "$blocked" 'has a push trigger'
workflow_blocks pull_request_target 'on: pull_request_target'
assert_not_contains "$blocked" 'has a push trigger'
fresh
stage "$workflow" 'on: [push, pull_request, pull_request_target, pull_request]'
blocks "$workflow" 'has a pull_request trigger' 'has a pull_request_target trigger'
assert_not_contains "$blocked" 'has a push trigger'
# Named twice in the file, it's still one thing to fix.
assert_exit 0 test "$(printf '%s\n' "$blocked" | grep -c 'has a pull_request trigger')" = 1

# Another file having the trigger doesn't help a new one.
fresh
stage .github/workflows/new.yml 'on: push'
blocks .github/workflows/new.yml 'has a push trigger'

# HEAD is what it's compared with, not the copy on disk.
fresh
stage "$workflow" 'on: [push, pull_request]'
printf 'on: push\n' >"$repo/$workflow"
blocks "$workflow" 'has a pull_request trigger'
fresh
stage "$workflow" 'name: edited
on: push'
printf 'on: [push, pull_request]\n' >"$repo/$workflow"
assert_exit 0 attempt

# Moved to another name inside the folder, a workflow keeps its triggers, however git
# is set to see a move. It needs enough content for git to see a move at all.
fresh
stage "$workflow" "on: push
$jobs"
git -C "$repo" commit -q --no-verify -m 'feat: longer workflow'
base=$(git -C "$repo" rev-parse HEAD)

moved=.github/workflows/moved.yml
for renames in true false; do
  fresh
  git -C "$repo" mv "$workflow" "$moved"
  assert_exit 0 git -C "$repo" -c "diff.renames=$renames" commit -q -m 'feat: x'
done
fresh
git -C "$repo" mv "$workflow" '.github/workflows/a b.yml'
assert_exit 0 attempt

# It can drop a trigger on the way, but not gain one.
fresh
git -C "$repo" mv "$workflow" "$moved"
stage "$moved" "on: workflow_dispatch
$jobs"
assert_exit 0 attempt
fresh
git -C "$repo" mv "$workflow" "$moved"
stage "$moved" "on: [push, pull_request]
$jobs"
blocks "$moved" 'has a pull_request trigger'
assert_not_contains "$blocked" 'has a push trigger'

# Rewritten past what git calls a move, it's a new file.
fresh
git -C "$repo" mv "$workflow" "$moved"
stage "$moved" 'on: push'
blocks "$moved" 'has a push trigger'

# Copied, it's a new file too, and the source stays.
fresh
mkdir -p "$repo/.github/workflows"
cp "$repo/$workflow" "$repo/$moved"
git -C "$repo" add "$moved"
blocks "$moved" 'has a push trigger'

# A file the allowlist covers isn't read at all, whatever its shape.
fresh
stage "$allowed" 'on: *x'
assert_exit 0 attempt

# A HEAD copy this can't read counts as having no triggers, so its new shape decides.
for unreadable_head in 'on: *x' 'on: [push, *x]'; do
  base=$trigger_base
  fresh
  stage "$workflow" "$unreadable_head"
  git -C "$repo" commit -q --no-verify -m 'feat: unreadable workflow'
  base=$(git -C "$repo" rev-parse HEAD)
  workflow_blocks push 'on: push'
  workflow_passes 'on: workflow_dispatch'
  workflow_unreadable 'on: *y'
done

# The first commit has no HEAD, so no triggers.
git -C "$repo" symbolic-ref HEAD refs/heads/first-commit
git -C "$repo" read-tree --empty
stage "$workflow" 'on: push'
blocks "$workflow" 'has a push trigger'
stage "$workflow" 'on: workflow_dispatch'
assert_exit 0 attempt
git -C "$repo" symbolic-ref HEAD refs/heads/main

# Back to a workflow with a push trigger, for what git makes of a move onto, off or
# into the allowlist and the folder.
base=$trigger_base
fresh
stage "$workflow" 'on: push'
git -C "$repo" commit -q --no-verify -m 'feat: push trigger'
base=$(git -C "$repo" rev-parse HEAD)

# On to the allowlist it passes, off the allowlist it doesn't.
fresh
git -C "$repo" mv "$workflow" "$allowed"
assert_exit 0 attempt
base=$(git -C "$repo" rev-parse HEAD)
fresh
git -C "$repo" mv "$allowed" .github/workflows/moved.yml
blocks .github/workflows/moved.yml push

# A file moved in from elsewhere is new to the folder.
base=$trigger_base
fresh
stage docs/x.yml 'on: push'
assert_exit 0 attempt
base=$(git -C "$repo" rev-parse HEAD)
fresh
mkdir -p "$repo/.github/workflows"
git -C "$repo" mv docs/x.yml "$workflow"
blocks "$workflow" push
base=$trigger_base

# So is one moved up from a subfolder, where GitHub wasn't running it.
fresh
stage .github/workflows/sub/x.yml 'on: push'
assert_exit 0 attempt
base=$(git -C "$repo" rev-parse HEAD)
fresh
git -C "$repo" mv .github/workflows/sub/x.yml "$workflow"
blocks "$workflow" push
base=$trigger_base

# --- A broken env file blocks, and a missing one warns and checks what it still can

# Missing: formatters can't run, and the workflow check works with no allowlist. A
# value in the caller's environment isn't the project's allowlist.
rm "$hooks/dev-workflow.env"
fresh
stage b.rs 'BAD'
warned=$(env 'DW_FORMATTERS=*.rs|./fmt' git -C "$repo" commit -q -m 'feat: x' 2>&1) ||
  _assert_fail "expected the commit to pass: $warned"
assert_contains "$warned" 'dev-workflow.env'
assert_contains "$warned" 'warning'
log_is ''

fresh
stage "$workflow" 'on: push'
blocks "$workflow" push 'dev-workflow.env' 'warning'

fresh
stage "$allowed" 'on: push'
blocks "$allowed" push
fresh
stage "$allowed" 'on: push'
assert_exit 1 env "DW_CI_ALLOWLIST=$allowed" git -C "$repo" commit -q -m 'feat: x'

fresh
stage "$workflow" 'on: workflow_dispatch'
assert_exit 0 attempt

fresh
warned=$(attempt --allow-empty 2>&1)
assert_contains "$warned" 'warning'

# Broken: nobody knows what it held, so nothing passes, not even an empty commit.
for broken in syntax failing unreadable empty truncated no-formatters no-allowlist; do
  write_env '*.rs|./fmt' ''
  case $broken in
    syntax) printf "DW_CHECK='unterminated\n" >"$hooks/dev-workflow.env" ;;
    failing) printf 'DW_CHECK=x\nfalse\n' >"$hooks/dev-workflow.env" ;;
    unreadable) chmod 000 "$hooks/dev-workflow.env" ;;
    empty) : >"$hooks/dev-workflow.env" ;;
    truncated) printf "DW_DEFAULT_BRANCH='main'\nDW_CHECK='x'\n" >"$hooks/dev-workflow.env" ;;
    no-formatters) printf "DW_CI_ALLOWLIST=''\n" >"$hooks/dev-workflow.env" ;;
    no-allowlist) printf "DW_FORMATTERS='*.rs|./fmt'\n" >"$hooks/dev-workflow.env" ;;
  esac
  fresh
  assert_exit 1 attempt --allow-empty
  blocked=$(attempt --allow-empty 2>&1)
  assert_contains "$blocked" 'pre-commit: '
  assert_contains "$blocked" 'dev-workflow.env'
  assert_not_contains "$blocked" 'warning'
  log_is ''
  fresh
  stage b.rs 'BAD'
  blocks 'dev-workflow.env'
  # The caller's environment can't fill in what the file left out.
  assert_exit 1 env 'DW_FORMATTERS=' 'DW_CI_ALLOWLIST=' git -C "$repo" commit -q -m 'feat: x'
  chmod 644 "$hooks/dev-workflow.env"
done

# No warning at all when the file is there.
write_env '' ''
fresh
assert_not_contains "$(attempt --allow-empty 2>&1)" 'warning'

# --- When git itself fails, the hook can't say the commit is clean

# Git puts its own folder first on a hook's PATH, so this runs the hook directly.
shim="$scratch/shim"
mkdir -p "$shim"
real_git=$(command -v git)
cat >"$shim/git" <<SHIM
#!/bin/sh
case "\$*" in
  \$FAIL_GIT)
    echo 'git failed for the test' >&2
    exit 128
    ;;
esac
exec "$real_git" "\$@"
SHIM
chmod +x "$shim/git"

run_hook_failing_git() { # <pattern for the git arguments to fail>
  (cd "$repo" && PATH="$shim:$PATH" FAIL_GIT=$1 .githooks/pre-commit)
}

write_env '' ''
fresh
stage "$workflow" 'on: workflow_dispatch'
assert_exit 0 run_hook_failing_git none
assert_exit 1 run_hook_failing_git 'diff --cached*'
assert_contains "$(run_hook_failing_git 'diff --cached*' 2>&1)" 'could not list the staged files'
assert_exit 1 run_hook_failing_git 'show*'
assert_contains "$(run_hook_failing_git 'show*' 2>&1)" "$workflow"

# Unstaged files decide whether a formatter can be trusted.
write_env '*.rs|./fmt' ''
fresh
stage b.rs 'clean'
assert_exit 0 run_hook_failing_git none
assert_exit 1 run_hook_failing_git 'diff --name-only'
assert_contains "$(run_hook_failing_git 'diff --name-only' 2>&1)" 'could not list the unstaged files'

# If git can't show what HEAD holds, or that a file moved, the trigger counts as gained.
write_env '' ''
fresh
stage "$workflow" 'on: push'
git -C "$repo" commit -q --no-verify -m 'feat: push trigger'
base=$(git -C "$repo" rev-parse HEAD)
fresh
stage "$workflow" 'name: edited
on: push'
assert_exit 0 run_hook_failing_git none
assert_exit 1 run_hook_failing_git 'show HEAD:*'
assert_contains "$(run_hook_failing_git 'show HEAD:*' 2>&1)" 'has a push trigger'
fresh
git -C "$repo" mv "$workflow" .github/workflows/moved.yml
assert_exit 0 run_hook_failing_git none
assert_exit 1 run_hook_failing_git '*--name-status*'
assert_contains "$(run_hook_failing_git '*--name-status*' 2>&1)" 'has a push trigger'

# --- A missing library can't check anything, so it blocks, and says why

fresh
rm "$hooks/dw-lib.sh"
assert_exit 1 attempt --allow-empty
assert_contains "$(attempt --allow-empty 2>&1)" 'dw-lib.sh is missing'
