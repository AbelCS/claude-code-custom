#!/bin/sh
# Fails if the plugin contains a term from the private, git-ignored term file:
# one case-insensitive term per line, matched as literal text in file contents
# and in file and folder names. LEAK_TERMS_FILE and LEAK_SEARCH_ROOT override
# the defaults.

root=$(cd "$(dirname "$0")/../.." && pwd)
terms_file=${LEAK_TERMS_FILE:-$root/.leak-terms.local}
search_root=${LEAK_SEARCH_ROOT:-$root/plugins/dev-workflow}

if [ ! -f "$terms_file" ]; then
  echo "leak test: term file not found: $terms_file (create it, git-ignored, with one term per line)" >&2
  exit 1
fi
if ! (cd "$search_root") 2>/dev/null; then
  echo "leak test: folder to search not found: $search_root" >&2
  exit 1
fi

term_count=0
leak_count=0
# read trims the spaces around each term; the || keeps a last line with no newline.
while read -r term || [ -n "$term" ]; do
  [ -n "$term" ] || continue
  term_count=$((term_count + 1))
  # Paths are relative, so the folders leading to the search root don't count.
  hits=$(
    cd "$search_root" || exit 1
    {
      find . -type f -exec grep -Fil -- "$term" {} +
      find . | grep -Fi -- "$term"
    } | sort -u
  )
  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    leak_count=$((leak_count + 1))
    echo "leak: ${hit#./} contains \"$term\"" >&2
  done <<HITS
$hits
HITS
done <"$terms_file"

if [ "$term_count" -eq 0 ]; then
  echo "leak test: no terms in $terms_file (one term per line)" >&2
  exit 1
fi
if [ "$leak_count" -gt 0 ]; then
  echo "leak test: $leak_count leak(s) in $search_root" >&2
  exit 1
fi
