#!/bin/sh
# Fails if a term from the private, git-ignored term file is in a file's
# contents or path: one case-insensitive term per line, matched as literal text.
# Anything it can't read fails too, because a leak could be behind it.
#
# It searches every git-tracked file in the repo, staged ones included, and no
# untracked or ignored file: this repo is public, so what counts is what is
# committed. LEAK_TERMS_FILE replaces the term file, and LEAK_SEARCH_ROOT searches
# every file in a folder instead.

root=$(cd "$(dirname "$0")/../.." && pwd)
terms_file=${LEAK_TERMS_FILE:-$root/.leak-terms.local}

fail() {
  printf 'leak test: %s\n' "$*" >&2
  exit 1
}

[ -f "$terms_file" ] || fail "term file not found: $terms_file (create it, git-ignored, with one term per line)"
# Drop a Windows file's carriage returns, or no term would ever match.
terms=$(tr -d '\r' <"$terms_file") || fail "could not read the term file: $terms_file"

errors=$(mktemp) || fail "could not create a temp file"
trap 'rm -f "$errors"' EXIT

# Paths are relative, so the folders leading to the search don't count.
if [ -n "${LEAK_SEARCH_ROOT:-}" ]; then
  cd "$LEAK_SEARCH_ROOT" 2>/dev/null || fail "folder to search not found: $LEAK_SEARCH_ROOT"
  paths=$(find . -type f 2>>"$errors")
else
  cd "$root" || fail "could not enter $root"
  # -z stops git quoting unusual names. A name with a newline in it comes out as
  # two paths that don't exist, which fails below.
  paths=$(git ls-files -z 2>>"$errors" | tr '\0' '\n')
fi

# Keep the files in the arguments: unusual names survive, and grep gets them all
# at once. A tracked symlink has only its name to search; its target is either
# tracked itself or not part of the repo.
set --
while IFS= read -r path; do
  [ -n "$path" ] || continue
  if [ -L "$path" ]; then
    continue
  elif [ -f "$path" ]; then
    set -- "$@" "$path"
  else
    echo "not found or not a file: $path" >>"$errors"
  fi
done <<PATHS
$paths
PATHS

# An empty search would pass everything, and grep would read its input instead.
[ "$#" -gt 0 ] || fail "nothing to search in $PWD
$(sort -u "$errors")"

term_count=0
leak_count=0
# read trims the spaces around each term.
while read -r term; do
  [ -n "$term" ] || continue
  term_count=$((term_count + 1))

  in_contents=$(grep -Fil -- "$term" "$@" 2>>"$errors")
  # 0 is a match and 1 is none. Anything else, or anything on stderr, is an error.
  [ "$?" -le 1 ] || echo "grep failed on term: $term" >>"$errors"
  in_paths=$(printf '%s\n' "$paths" | grep -Fi -- "$term")

  hits=$(printf '%s\n%s\n' "$in_contents" "$in_paths" | sort -u)
  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    leak_count=$((leak_count + 1))
    echo "leak: ${hit#./} contains \"$term\"" >&2
  done <<HITS
$hits
HITS
done <<TERMS
$terms
TERMS

[ "$term_count" -gt 0 ] || fail "no terms in $terms_file (one term per line)"
if [ -s "$errors" ]; then
  fail "could not search everything in $PWD:
$(sort -u "$errors")"
fi
[ "$leak_count" -eq 0 ] || fail "$leak_count leak(s) in $PWD"
