#!/bin/sh
# Assertions and helpers for tests. Source this file; don't run it.
#
# A failing assertion prints why and exits the test process, so a test can't
# carry on and pass after a failure. Sourcing this file sets an EXIT trap: a
# test that needs its own trap must also keep this one's cleanup.

# Git hooks export these, and they would point every fixture at the real repo.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE

_assert_tmp_root=$(mktemp -d "${TMPDIR:-/tmp}/dev-workflow-test.XXXXXX") || exit 1
trap 'rm -rf "$_assert_tmp_root"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

_assert_fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

# assert_exit <code> <cmd...>: runs cmd in a subshell, so a function that exits
# is measured too, and fails unless it exits with code.
assert_exit() {
  _assert_expected=$1
  shift
  if _assert_output=$("$@" 2>&1); then
    _assert_actual=0
  else
    _assert_actual=$?
  fi
  [ "$_assert_actual" -eq "$_assert_expected" ] && return 0
  _assert_fail "expected exit $_assert_expected, got $_assert_actual: $*
$_assert_output"
}

# assert_contains <text> <needle>: the needle is literal text.
assert_contains() {
  case "$1" in
    *"$2"*) return 0 ;;
  esac
  _assert_fail "expected to find \"$2\" in:
$1"
}

# assert_not_contains <text> <needle>: the needle is literal text.
assert_not_contains() {
  case "$1" in
    *"$2"*) _assert_fail "expected not to find \"$2\" in:
$1" ;;
  esac
}

# assert_file_same <a> <b>: fails if the files differ or either is missing.
assert_file_same() {
  cmp -s "$1" "$2" || _assert_fail "files differ: $1 $2"
}

# new_repo <dir>: a git repo with an identity, default branch main and no
# commit signing, so it behaves the same on every machine.
new_repo() {
  if ! {
    mkdir -p "$1" &&
      git -C "$1" init -q -b main &&
      git -C "$1" config user.name "Test" &&
      git -C "$1" config user.email "test@example.com" &&
      git -C "$1" config commit.gpgsign false
  }; then
    _assert_fail "could not create a repo in $1"
  fi
}

# tmp_dir: prints a new empty directory, removed when the test process exits.
tmp_dir() {
  mktemp -d "$_assert_tmp_root/XXXXXX" || _assert_fail "could not create a temp directory"
}
