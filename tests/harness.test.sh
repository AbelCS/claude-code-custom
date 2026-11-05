#!/bin/sh
# Tests the test harness itself: the assertions, tests/run.sh, scripts/check,
# scripts/verify and .gitignore.

ROOT=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=tests/lib/assert.sh
. "$ROOT/tests/lib/assert.sh"

# Passes only if the assertion given as arguments fails. Uses no assertion
# itself, so a broken assert_exit can't hide a broken assert_exit.
must_fail() {
  if ("$@") >/dev/null 2>&1; then
    echo "FAIL: expected this to fail: $*" >&2
    exit 1
  fi
}

# --- assert_exit

assert_exit 0 true
must_fail assert_exit 0 false
assert_exit 3 sh -c 'exit 3'
must_fail assert_exit 2 true

# A failing assertion reports what the command printed.
message=$( (assert_exit 0 sh -c 'echo from-the-command; exit 1') 2>&1)
assert_contains "$message" "from-the-command"

# --- assert_contains, assert_not_contains

assert_contains "abc" "b"
must_fail assert_contains "abc" "z"
assert_not_contains "abc" "z"
must_fail assert_not_contains "abc" "b"
# The needle is literal text, not a pattern.
must_fail assert_contains "abc" "a*c"

# --- assert_file_same

files=$(tmp_dir)
printf 'one\n' >"$files/a"
printf 'one\n' >"$files/b"
printf 'two\n' >"$files/c"
assert_file_same "$files/a" "$files/b"
must_fail assert_file_same "$files/a" "$files/c"
must_fail assert_file_same "$files/a" "$files/missing"

# --- new_repo

# It doesn't lean on this machine's git config: here there is no identity and
# the default branch is something else.
repo="$(tmp_dir)/nested/repo"
(
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
  export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=init.defaultBranch GIT_CONFIG_VALUE_0=other
  new_repo "$repo"
  assert_exit 0 test "$(git -C "$repo" symbolic-ref --short HEAD)" = main
  assert_exit 0 git -C "$repo" config user.name
  assert_exit 0 git -C "$repo" config user.email
  assert_exit 0 git -C "$repo" commit -q --allow-empty -m "first"
) || exit 1

# Git hooks export GIT_DIR, and a repo the hook runs in must stay untouched.
hook_repo=$(tmp_dir)
git init -q "$hook_repo"
GIT_DIR="$hook_repo/.git" sh -c '. "$1"; new_repo "$(tmp_dir)/repo"' sh "$ROOT/tests/lib/assert.sh"
assert_exit 1 git -C "$hook_repo" config --local user.name

# --- tmp_dir

first=$(tmp_dir)
second=$(tmp_dir)
assert_exit 0 test -d "$first"
assert_exit 0 test "$first" != "$second"

# It is gone once the process that asked for it exits.
left_behind=$(sh -c '. "$1"; tmp_dir' sh "$ROOT/tests/lib/assert.sh")
assert_exit 0 test -n "$left_behind"
assert_exit 1 test -e "$left_behind"

# --- tests/run.sh

run_sh="$ROOT/tests/run.sh"

write_test() { # <path> <body>
  mkdir -p "$(dirname "$1")"
  printf '%s\n' "$2" >"$1"
}

# One failing test: non-zero, counted, and its output shown.
one_failing=$(tmp_dir)
write_test "$one_failing/bad.test.sh" 'echo why-it-failed; exit 1'
assert_exit 1 sh "$run_sh" "$one_failing"
output=$(sh "$run_sh" "$one_failing" 2>&1)
assert_contains "$output" "0 passed, 1 failed"
assert_contains "$output" "why-it-failed"

# All passing, in nested folders and paths with spaces.
all_passing=$(tmp_dir)
write_test "$all_passing/good.test.sh" 'exit 0'
write_test "$all_passing/sub folder/also good.test.sh" 'exit 0'
assert_exit 0 sh "$run_sh" "$all_passing"
assert_contains "$(sh "$run_sh" "$all_passing" 2>&1)" "2 passed, 0 failed"

# Only *.test.sh files run, and verify_only/ is skipped.
skipped=$(tmp_dir)
write_test "$skipped/good.test.sh" 'exit 0'
write_test "$skipped/helper.sh" 'exit 1'
write_test "$skipped/verify_only/slow.test.sh" 'exit 1'
assert_exit 0 sh "$run_sh" "$skipped"
assert_contains "$(sh "$run_sh" "$skipped" 2>&1)" "1 passed, 0 failed"

# Each test has its own process: one that exits early doesn't end the run.
own_process=$(tmp_dir)
write_test "$own_process/a.test.sh" 'exit 0'
write_test "$own_process/b.test.sh" 'exit 1'
assert_contains "$(sh "$run_sh" "$own_process" 2>&1)" "1 passed, 1 failed"

# A test that reads its input can't swallow the rest of the list.
reads_stdin=$(tmp_dir)
write_test "$reads_stdin/a.test.sh" 'cat >/dev/null'
write_test "$reads_stdin/b.test.sh" 'exit 1'
assert_contains "$(sh "$run_sh" "$reads_stdin" 2>&1)" "1 passed, 1 failed"

# What a passing test prints is shown, so a skip can't go unnoticed.
says_skip=$(tmp_dir)
write_test "$says_skip/a.test.sh" 'echo "SKIP: not on this machine"'
assert_contains "$(sh "$run_sh" "$says_skip" 2>&1)" "SKIP: not on this machine"

# Finding nothing to run is a failure, never a pass.
assert_exit 1 sh "$run_sh" "$(tmp_dir)"
assert_exit 1 sh "$run_sh" "$(tmp_dir)/missing"

# --- scripts/check and scripts/verify
#
# These run on a copy of the scripts in a temp repo, with stand-ins for
# tests/run.sh, claude and uvx: the real check runs this very file.

stub_bin=$(tmp_dir)
export STUB_LOG="$stub_bin/log"
export STUB_UVX_ARGS="$stub_bin/uvx-args"
export STUB_FAIL_ON=""

write_stub() { # <path> <label> <logged text>
  cat >"$1" <<STUB
#!/bin/sh
echo "$3" >>"\$STUB_LOG"
[ "\$STUB_FAIL_ON" != "$2" ]
STUB
  chmod +x "$1"
}

cat >"$stub_bin/claude" <<'STUB'
#!/bin/sh
echo "claude $*" >>"$STUB_LOG"
[ "$STUB_FAIL_ON" != "claude $3" ]
STUB
chmod +x "$stub_bin/claude"
cat >"$stub_bin/uvx" <<'STUB'
#!/bin/sh
echo "uvx" >>"$STUB_LOG"
printf '%s\n' "$@" >"$STUB_UVX_ARGS"
[ "$STUB_FAIL_ON" != "uvx" ]
STUB
chmod +x "$stub_bin/uvx"

new_fixture() {
  fixture=$(tmp_dir)
  new_repo "$fixture"
  mkdir -p "$fixture/scripts" "$fixture/tests"
  cp "$ROOT/scripts/check" "$ROOT/scripts/verify" "$fixture/scripts/"
  write_stub "$fixture/tests/run.sh" 'run.sh' 'run.sh'
  : >"$STUB_LOG"
  printf '%s\n' "$fixture"
}

run_stubbed() { # <script> <fixture>
  PATH="$stub_bin:$PATH" sh "$2/scripts/$1" 2>&1
}

# check runs its four steps in order, stopping with a failure at any of them.
fixture=$(new_fixture)
assert_exit 0 run_stubbed check "$fixture"
expected="$stub_bin/expected"
cat >"$expected" <<'LOG'
run.sh
claude plugin validate plugins/dev-workflow
claude plugin validate .
uvx
LOG
assert_file_same "$STUB_LOG" "$expected"

for STUB_FAIL_ON in run.sh 'claude plugins/dev-workflow' 'claude .' uvx; do
  assert_exit 1 run_stubbed check "$fixture"
done
STUB_FAIL_ON=""

# A step that fails stops the steps after it.
fixture=$(new_fixture)
STUB_FAIL_ON=run.sh
assert_exit 1 run_stubbed check "$fixture"
STUB_FAIL_ON=""
assert_contains "$(cat "$STUB_LOG")" "run.sh"
assert_not_contains "$(cat "$STUB_LOG")" "claude"

# The lint gets every shell file git would keep, found by name or first line.
fixture=$(new_fixture)
printf 'ignored.sh\n' >"$fixture/.gitignore"
printf 'echo no shebang\n' >"$fixture/tests/with space.sh"
printf '#!/bin/sh\n' >"$fixture/sh-hook"
printf '#!/usr/bin/env bash\n' >"$fixture/bash-tool"
printf '#!/usr/bin/env python3\n' >"$fixture/python-tool"
printf '# Notes\n' >"$fixture/notes.md"
printf '#!/bin/sh\n' >"$fixture/ignored.sh"
printf '#!/bin/sh\n' >"$fixture/gone.sh"
git -C "$fixture" add gone.sh
git -C "$fixture" commit -q -m "add a file to delete"
rm "$fixture/gone.sh"
assert_exit 0 run_stubbed check "$fixture"
assert_contains "$(head -n 3 "$STUB_UVX_ARGS")" "--from
shellcheck-py
shellcheck"
for shell_file in scripts/check scripts/verify tests/run.sh 'tests/with space.sh' sh-hook bash-tool; do
  assert_exit 0 grep -Fx "$shell_file" "$STUB_UVX_ARGS"
done
for other_file in python-tool notes.md ignored.sh gone.sh; do
  assert_exit 1 grep -Fx "$other_file" "$STUB_UVX_ARGS"
done

# A missing uvx or claude fails with its name, before anything runs.
run_with_only() { # <bin dir> <fixture>
  PATH="$1" /bin/sh "$2/scripts/check" 2>&1
}
fixture=$(new_fixture)
only_claude=$(tmp_dir)
cp "$stub_bin/claude" "$only_claude/"
assert_exit 1 run_with_only "$only_claude" "$fixture"
output=$(run_with_only "$only_claude" "$fixture")
assert_contains "$output" "uvx"
assert_not_contains "$output" "claude"
only_uvx=$(tmp_dir)
cp "$stub_bin/uvx" "$only_uvx/"
assert_exit 1 run_with_only "$only_uvx" "$fixture"
output=$(run_with_only "$only_uvx" "$fixture")
assert_contains "$output" "claude"
assert_not_contains "$output" "uvx"
assert_exit 0 test ! -s "$STUB_LOG"

# verify runs check, then every verify_only test, which run.sh leaves out.
fixture=$(new_fixture)
mkdir -p "$fixture/tests/verify_only"
write_stub "$fixture/tests/verify_only/a.test.sh" 'a' 'verify_only a'
write_stub "$fixture/tests/verify_only/b.test.sh" 'b' 'verify_only b'
assert_exit 0 run_stubbed verify "$fixture"
cat >"$expected" <<'LOG'
run.sh
claude plugin validate plugins/dev-workflow
claude plugin validate .
uvx
verify_only a
verify_only b
LOG
assert_file_same "$STUB_LOG" "$expected"

# A failing verify_only test fails verify, is named, and the others still run.
: >"$STUB_LOG"
STUB_FAIL_ON=a
assert_exit 1 run_stubbed verify "$fixture"
STUB_FAIL_ON=""
assert_contains "$(tail -n 1 "$STUB_LOG")" "verify_only b"
STUB_FAIL_ON=a
output=$(run_stubbed verify "$fixture")
STUB_FAIL_ON=""
assert_contains "$output" "a.test.sh"

# A failing check fails verify, without running the verify_only tests.
: >"$STUB_LOG"
STUB_FAIL_ON=uvx
assert_exit 1 run_stubbed verify "$fixture"
STUB_FAIL_ON=""
assert_not_contains "$(cat "$STUB_LOG")" "verify_only"

# No verify_only tests to run is a failure, never a pass.
fixture=$(new_fixture)
assert_exit 1 run_stubbed verify "$fixture"

# The scripts run directly.
for script in scripts/check scripts/verify tests/run.sh; do
  assert_exit 0 test -x "$ROOT/$script"
done

# --- .gitignore

for ignored in .DS_Store plugins/.DS_Store .leak-terms.local \
  plugins/any/evals/results/run.json .claude/settings.local.json; do
  assert_exit 0 git -C "$ROOT" -c core.excludesFile=/dev/null check-ignore -q "$ignored"
done

# --- tests/verify_only/leak.test.sh

leak_test="$ROOT/tests/verify_only/leak.test.sh"

run_leak() { # <terms file> <search root>
  LEAK_TERMS_FILE=$1 LEAK_SEARCH_ROOT=$2 sh "$leak_test" 2>&1
}

terms="$(tmp_dir)/terms"
printf 'acme\nglobal widgets\n' >"$terms"

# Passes when no term is there.
clean=$(tmp_dir)
printf 'Nothing to see here.\n' >"$clean/notes.md"
assert_exit 0 run_leak "$terms" "$clean"

# A missing term file fails, saying which file and what to do.
assert_exit 1 run_leak "$terms.missing" "$clean"
output=$(run_leak "$terms.missing" "$clean")
assert_contains "$output" "$terms.missing"
assert_contains "$output" "one term per line"

# A term file without terms would pass everything, so it fails too.
no_terms="$(tmp_dir)/terms"
printf '\n   \n' >"$no_terms"
assert_exit 1 run_leak "$no_terms" "$clean"
assert_contains "$(run_leak "$no_terms" "$clean")" "$no_terms"

# A folder that isn't there would pass everything, so it fails too.
assert_exit 1 run_leak "$terms" "$clean/missing"
assert_contains "$(run_leak "$terms" "$clean/missing")" "$clean/missing"

# A term in a file fails, naming the file and the term, whatever the case.
leaking=$(tmp_dir)
mkdir -p "$leaking/deep/down"
printf 'Built for ACME people.\n' >"$leaking/deep/down/notes.md"
assert_exit 1 run_leak "$terms" "$leaking"
output=$(run_leak "$terms" "$leaking")
assert_contains "$output" "deep/down/notes.md"
assert_contains "$output" "acme"
assert_not_contains "$output" "global widgets"

# Terms can have several words, and every leak is reported.
printf 'Our Global Widgets line.\n' >"$leaking/other.md"
output=$(run_leak "$terms" "$leaking")
assert_contains "$output" "deep/down/notes.md"
assert_contains "$output" "other.md"
assert_contains "$output" "global widgets"

# A term in a file or folder name is a leak as well.
in_name=$(tmp_dir)
mkdir -p "$in_name/acme-parts"
printf 'Nothing here.\n' >"$in_name/acme-parts/notes.md"
assert_exit 1 run_leak "$terms" "$in_name"
assert_contains "$(run_leak "$terms" "$in_name")" "acme-parts"

# Only the search root's insides count, not the path leading to it.
named_parent="$(tmp_dir)/acme"
mkdir -p "$named_parent"
printf 'Nothing here.\n' >"$named_parent/notes.md"
assert_exit 0 run_leak "$terms" "$named_parent"

# Blank lines match nothing, spaces around a term don't count, and the last
# line needs no newline.
messy="$(tmp_dir)/terms"
printf '\n  \n  padded  \n\nunfinished' >"$messy"
assert_exit 0 run_leak "$messy" "$clean"
padded=$(tmp_dir)
printf 'A padded line.\n' >"$padded/notes.md"
assert_exit 1 run_leak "$messy" "$padded"
unfinished=$(tmp_dir)
printf 'An unfinished line.\n' >"$unfinished/notes.md"
assert_exit 1 run_leak "$messy" "$unfinished"

# Terms are literal text, not patterns.
literal="$(tmp_dir)/terms"
printf 'a.c\n-x\n' >"$literal"
not_literal=$(tmp_dir)
printf 'abc\n' >"$not_literal/notes.md"
assert_exit 0 run_leak "$literal" "$not_literal"
dash_term=$(tmp_dir)
printf 'run it with -x here\n' >"$dash_term/notes.md"
assert_exit 1 run_leak "$literal" "$dash_term"

# Anything it can't read fails, because a leak could be behind it. Permissions
# don't stop root, so these can't run as root. Each restores the mode before
# asserting, so the temp folder can always be removed.
if [ "$(id -u)" -eq 0 ]; then
  can_lock_files=false
  echo "SKIP: leak test on unreadable files and folders: running as root"
else
  can_lock_files=true
fi

if "$can_lock_files"; then
  locked_folder=$(tmp_dir)
  printf 'Nothing here.\n' >"$locked_folder/notes.md"
  mkdir "$locked_folder/sub"
  printf 'acme\n' >"$locked_folder/sub/notes.md"
  chmod 000 "$locked_folder/sub"
  output=$(run_leak "$terms" "$locked_folder")
  code=$?
  chmod 755 "$locked_folder/sub"
  assert_exit 0 test "$code" -eq 1
  assert_contains "$output" "sub"

  locked_file=$(tmp_dir)
  printf 'Nothing here.\n' >"$locked_file/notes.md"
  printf 'acme\n' >"$locked_file/x"
  chmod 000 "$locked_file/x"
  output=$(run_leak "$terms" "$locked_file")
  code=$?
  chmod 644 "$locked_file/x"
  assert_exit 0 test "$code" -eq 1
  assert_contains "$output" "x"

  locked_terms="$(tmp_dir)/terms"
  printf 'acme\n' >"$locked_terms"
  chmod 000 "$locked_terms"
  output=$(run_leak "$locked_terms" "$clean")
  code=$?
  chmod 644 "$locked_terms"
  assert_exit 0 test "$code" -eq 1
  assert_contains "$output" "$locked_terms"
fi

# A term file with Windows line endings still matches.
crlf_terms="$(tmp_dir)/terms"
printf 'first\r\nacme\r\n' >"$crlf_terms"
crlf_leak=$(tmp_dir)
printf 'Built for acme people.\n' >"$crlf_leak/notes.md"
assert_exit 1 run_leak "$crlf_terms" "$crlf_leak"
assert_contains "$(run_leak "$crlf_terms" "$crlf_leak")" "notes.md contains \"acme\""
assert_exit 0 run_leak "$crlf_terms" "$clean"

# By default it reads .leak-terms.local and searches every tracked file in the
# repo, and nothing else.
default_repo=$(tmp_dir)
default_leak="$default_repo/tests/verify_only/leak.test.sh"
new_repo "$default_repo"
mkdir -p "$default_repo/tests/verify_only" "$default_repo/docs" "$default_repo/plugins/dev-workflow"
cp "$leak_test" "$default_repo/tests/verify_only/"
printf 'Nothing here.\n' >"$default_repo/plugins/dev-workflow/notes.md"
printf 'Nothing here.\n' >"$default_repo/docs/notes.md"
printf '.leak-terms.local\nignored.md\nignored-folder/\n' >"$default_repo/.gitignore"
git -C "$default_repo" add .
git -C "$default_repo" commit -q -m "first"

# The term file is required, and a clean repo passes.
assert_exit 1 sh "$default_leak"
assert_contains "$(sh "$default_leak" 2>&1)" ".leak-terms.local"
printf 'acme\n' >"$default_repo/.leak-terms.local"
assert_exit 0 sh "$default_leak"

# Git-ignored and untracked files don't count, in their contents or names.
mkdir -p "$default_repo/ignored-folder"
printf 'acme\n' >"$default_repo/ignored.md"
printf 'acme\n' >"$default_repo/ignored-folder/notes.md"
printf 'acme\n' >"$default_repo/ignored-folder/acme.md"
printf 'acme\n' >"$default_repo/untracked.md"
printf 'Nothing here.\n' >"$default_repo/acme-untracked.md"
assert_exit 0 sh "$default_leak"
rm "$default_repo/acme-untracked.md"

# A staged file counts as tracked.
git -C "$default_repo" add untracked.md
assert_exit 1 sh "$default_leak"
assert_contains "$(sh "$default_leak" 2>&1)" "untracked.md contains \"acme\""
git -C "$default_repo" rm -q -f --cached untracked.md
rm "$default_repo/untracked.md"

# A term in a committed file outside plugins/ fails.
printf 'Built for ACME people.\n' >"$default_repo/docs/notes.md"
git -C "$default_repo" commit -q -a -m "add a leak outside the plugins"
assert_exit 1 sh "$default_leak"
assert_contains "$(sh "$default_leak" 2>&1)" "docs/notes.md contains \"acme\""
printf 'Nothing here.\n' >"$default_repo/docs/notes.md"
git -C "$default_repo" commit -q -a -m "remove it"
assert_exit 0 sh "$default_leak"

# A term in a tracked file's name or folder fails.
mkdir -p "$default_repo/docs/acme-parts"
printf 'Nothing here.\n' >"$default_repo/docs/acme-parts/notes.md"
git -C "$default_repo" add docs/acme-parts/notes.md
assert_exit 1 sh "$default_leak"
assert_contains "$(sh "$default_leak" 2>&1)" "docs/acme-parts/notes.md"
git -C "$default_repo" rm -q -f docs/acme-parts/notes.md
assert_exit 0 sh "$default_leak"

# File names with spaces or non-ASCII characters are searched, and shown as is.
accented_name=$(printf 'docs/caf\303\251.md')
for unusual_name in 'docs/with space.md' "$accented_name"; do
  printf 'acme\n' >"$default_repo/$unusual_name"
  git -C "$default_repo" add "$unusual_name"
  assert_exit 1 sh "$default_leak"
  assert_contains "$(sh "$default_leak" 2>&1)" "$unusual_name contains \"acme\""
  git -C "$default_repo" rm -q -f "$unusual_name"
done
assert_exit 0 sh "$default_leak"

# A tracked file it can't find can't be vouched for.
printf 'Nothing here.\n' >"$default_repo/docs/gone.md"
git -C "$default_repo" add docs/gone.md
rm "$default_repo/docs/gone.md"
assert_exit 1 sh "$default_leak"
assert_contains "$(sh "$default_leak" 2>&1)" "docs/gone.md"
git -C "$default_repo" rm -q --cached docs/gone.md
assert_exit 0 sh "$default_leak"

# Tracked files it can't read fail the same way.
if "$can_lock_files"; then
  mkdir "$default_repo/locked"
  printf 'Nothing here.\n' >"$default_repo/locked/notes.md"
  printf 'Nothing here.\n' >"$default_repo/locked-file.md"
  git -C "$default_repo" add locked/notes.md locked-file.md

  chmod 000 "$default_repo/locked"
  output=$(sh "$default_leak" 2>&1)
  code=$?
  chmod 755 "$default_repo/locked"
  assert_exit 0 test "$code" -eq 1
  assert_contains "$output" "locked/notes.md"

  chmod 000 "$default_repo/locked-file.md"
  output=$(sh "$default_leak" 2>&1)
  code=$?
  chmod 644 "$default_repo/locked-file.md"
  assert_exit 0 test "$code" -eq 1
  assert_contains "$output" "locked-file.md"

  git -C "$default_repo" rm -q -f locked/notes.md locked-file.md
fi

# Git commits a tracked symlink's target text as its content, so that text is
# searched, whether or not it points at anything. The link's name counts too.
ln -s docs "$default_repo/folder-link"
ln -s missing "$default_repo/broken-link"
git -C "$default_repo" add folder-link broken-link
assert_exit 0 sh "$default_leak"
ln -s /Users/ACME/secret "$default_repo/secret-link"
git -C "$default_repo" add secret-link
assert_exit 1 sh "$default_leak"
output=$(sh "$default_leak" 2>&1)
assert_contains "$output" "secret-link"
assert_contains "$output" "contains \"acme\""
git -C "$default_repo" rm -q -f secret-link
assert_exit 0 sh "$default_leak"
ln -s docs "$default_repo/acme-link"
git -C "$default_repo" add acme-link
assert_exit 1 sh "$default_leak"
git -C "$default_repo" rm -q -f acme-link folder-link broken-link
assert_exit 0 sh "$default_leak"

# Nothing to search is a failure, never a pass.
assert_exit 1 run_leak "$terms" "$(tmp_dir)"
empty_repo=$(tmp_dir)
new_repo "$empty_repo"
mkdir -p "$empty_repo/tests/verify_only"
cp "$leak_test" "$empty_repo/tests/verify_only/"
printf 'acme\n' >"$empty_repo/.leak-terms.local"
assert_exit 1 sh "$empty_repo/tests/verify_only/leak.test.sh"
assert_contains "$(sh "$empty_repo/tests/verify_only/leak.test.sh" 2>&1)" "nothing to search"

# Outside a git repo there is no list of tracked files, which is a failure.
not_a_repo=$(tmp_dir)
mkdir -p "$not_a_repo/tests/verify_only"
cp "$leak_test" "$not_a_repo/tests/verify_only/"
printf 'acme\n' >"$not_a_repo/.leak-terms.local"
assert_exit 1 sh "$not_a_repo/tests/verify_only/leak.test.sh"

# Pointed at a folder, it searches all of that folder, tracked or not, even
# inside a repo.
printf 'acme\n' >"$default_repo/ignored-folder/more.md"
assert_exit 1 env LEAK_SEARCH_ROOT="$default_repo/ignored-folder" sh "$default_leak"
