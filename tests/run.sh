#!/bin/sh
# Usage: tests/run.sh [dir]
#
# Runs every *.test.sh under dir (default: this folder), skipping verify_only/,
# each in its own process and all at once, so a test can't rely on another or on
# anything outside its own temp folders. Results come in the list's order, each
# test's output under its name, whichever finishes first. Prints a count; exits
# non-zero if any test fails or none are found.

dir=${1:-$(dirname "$0")}

if [ ! -d "$dir" ]; then
  echo "run.sh: no such directory: $dir" >&2
  exit 1
fi

work=$(mktemp -d) || exit 1
pids=
trap 'rm -rf "$work"' EXIT

# A test started in the background ignores INT, so it has to be told.
stop() {
  # shellcheck disable=SC2086 # A list of numbers.
  [ -z "$pids" ] || kill $pids 2>/dev/null
  exit "$1"
}
trap 'stop 129' HUP
trap 'stop 130' INT
trap 'stop 143' TERM

# A find that fails or complains may have left tests out, and in a pipeline its
# failure would be lost.
if ! find "$dir" -type d -name verify_only -prune -o -type f -name '*.test.sh' -print >"$work/found" 2>"$work/errors" ||
  [ -s "$work/errors" ]; then
  echo "run.sh: could not list the tests in $dir" >&2
  cat "$work/errors" >&2
  exit 1
fi
sort "$work/found" >"$work/tests" || exit 1

number=0
while IFS= read -r test_file; do
  number=$((number + 1))
  # Stdin is the file list: a test must not be able to read it.
  sh "$test_file" >"$work/$number.out" 2>&1 </dev/null &
  pids="$pids $!"
done <"$work/tests"

# shellcheck disable=SC2086 # A list of numbers.
set -- $pids
number=0
passed=0
failed=0
while IFS= read -r test_file; do
  number=$((number + 1))
  output_file=$work/$number.out
  if wait "$1"; then
    passed=$((passed + 1))
    echo "ok      $test_file"
    [ ! -s "$output_file" ] || cat "$output_file"
  else
    failed=$((failed + 1))
    echo "not ok  $test_file"
    cat "$output_file"
  fi
  shift
done <"$work/tests"
[ $((passed + failed)) -gt 0 ] || echo "run.sh: no tests found in $dir" >&2
echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ] && [ "$passed" -gt 0 ]
