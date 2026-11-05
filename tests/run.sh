#!/bin/sh
# Usage: tests/run.sh [dir]
#
# Runs every *.test.sh under dir (default: this folder), skipping verify_only/,
# each in its own process. Prints a count; exits non-zero if any test fails or
# none are found.

dir=${1:-$(dirname "$0")}

if [ ! -d "$dir" ]; then
  echo "run.sh: no such directory: $dir" >&2
  exit 1
fi

find "$dir" -type d -name verify_only -prune -o -type f -name '*.test.sh' -print | sort | {
  passed=0
  failed=0
  while IFS= read -r test_file; do
    # Stdin is the file list: a test must not be able to read it.
    if output=$(sh "$test_file" 2>&1 </dev/null); then
      passed=$((passed + 1))
      echo "ok      $test_file"
      [ -z "$output" ] || printf '%s\n' "$output"
    else
      failed=$((failed + 1))
      echo "not ok  $test_file"
      printf '%s\n' "$output"
    fi
  done
  [ $((passed + failed)) -gt 0 ] || echo "run.sh: no tests found in $dir" >&2
  echo "$passed passed, $failed failed"
  [ "$failed" -eq 0 ] && [ "$passed" -gt 0 ]
}
