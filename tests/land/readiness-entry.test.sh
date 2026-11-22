#!/bin/sh
# check-entry.sh <root> <version>: whether docs/readiness.md holds that version's entry, in
# the one form raise-version.sh's gate reads, through the same library.

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
# shellcheck source=tests/lib/assert.sh
. "$ROOT/tests/lib/assert.sh"

CE="$ROOT/plugins/dev-workflow/scripts/readiness/check-entry.sh"
root=$(tmp_dir)
mkdir "$root/docs"

entry() { # <text>
  printf '%s\n' "$1" >"$root/docs/readiness.md"
}

entry '# Readiness

## 1.0.0, 2026-11-22

| Item | Outcome | Why |
|---|---|---|
| Security review | Done | No findings |'
assert_exit 0 sh "$CE" "$root" 1.0.0
assert_exit 1 sh "$CE" "$root" 2.0.0
# The heading is exact: a date, and nothing after it, and the version whole.
entry '## 1.0.0, 2026-11-22 (draft)'
assert_exit 1 sh "$CE" "$root" 1.0.0
entry '## 1.0.0'
assert_exit 1 sh "$CE" "$root" 1.0.0
entry '## 1.0.0-rc.1, 2026-11-22'
assert_exit 1 sh "$CE" "$root" 1.0.0
entry '## 1x0x0, 2026-11-22'
assert_exit 1 sh "$CE" "$root" 1.0.0
assert_contains "$(sh "$CE" "$root" 2.0.0 2>&1)" '## 2.0.0, YYYY-MM-DD'
rm "$root/docs/readiness.md"
assert_exit 1 sh "$CE" "$root" 1.0.0

assert_exit 2 sh "$CE"
assert_exit 2 sh "$CE" "$root" v1.0.0
