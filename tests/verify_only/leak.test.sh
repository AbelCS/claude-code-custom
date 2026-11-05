#!/bin/sh
# Fails if a term from the private, git-ignored term file is in a file's
# contents or path: one case-insensitive term per line, matched as literal text.
# Anything it can't read fails too, because a leak could be behind it. Its output
# reaches logs and agents, so it never shows a term: it gives the term's line in
# the term file, and withholds any path or error message that holds a term.
#
# It searches every git-tracked file in the repo as it is in the index, which is
# what would be committed, and no untracked or ignored file: this repo is public,
# so what counts is what is committed. LEAK_TERMS_FILE replaces the term file, and
# LEAK_SEARCH_ROOT searches every working file in a folder instead.

root=$(cd "$(dirname "$0")/../.." && pwd)
terms_file=${LEAK_TERMS_FILE:-$root/.leak-terms.local}

fail() {
  printf 'leak test: %s\n' "$*" >&2
  exit 1
}

[ -f "$terms_file" ] || fail "term file not found: $terms_file (create it, git-ignored, with one term per line)"
# Drop a Windows file's carriage returns, or no term would ever match.
terms=$(tr -d '\r' <"$terms_file") || fail "could not read the term file: $terms_file"

work=$(mktemp -d) || fail "could not create a temp folder"
trap 'rm -rf "$work"' EXIT
errors="$work/errors"
: >"$errors"

# The trimmed terms, to check what this test is about to print.
term_list="$work/terms"
printf '%s\n' "$terms" | sed 's/^[[:blank:]]*//; s/[[:blank:]]*$//' | grep -v '^$' >"$term_list"
[ -s "$term_list" ] || fail "no terms in $terms_file (one term per line)"

show_errors() {
  grep -Fiv -f "$term_list" "$errors" | sort -u >&2
  withheld=$(grep -Fi -f "$term_list" "$errors" | sort -u | wc -l | tr -d ' ')
  [ "$withheld" -eq 0 ] || echo "leak test: $withheld error message(s) withheld because they hold a term" >&2
}

report_leak() { # <path> <term's line>
  if printf '%s\n' "$1" | grep -Fiq -f "$term_list"; then
    place=$(printf '%s\n' "$paths" | grep -nFx -- "$1" | head -n 1 | cut -d: -f1)
    echo "leak: path $place of the list from '$list_command' matches term on line $2 of the term file (name withheld: it holds a term)" >&2
  else
    echo "leak: ${1#./} matches term on line $2 of the term file" >&2
  fi
}

nothing_to_search() {
  echo "leak test: nothing to search" >&2
  show_errors
  exit 1
}

tab=$(printf '\t')
links=""

# Paths are relative, so the folders leading to the search don't count.
set --
if [ -n "${LEAK_SEARCH_ROOT:-}" ]; then
  cd "$LEAK_SEARCH_ROOT" 2>/dev/null || fail "folder to search not found: $LEAK_SEARCH_ROOT"
  list_command='find . -type f'
  paths=$(find . -type f 2>>"$errors")

  # Keep the files in the arguments: unusual names survive, and grep gets them
  # all at once.
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    if [ -f "$path" ]; then
      set -- "$@" "$path"
    else
      echo "not found or not a file: $path" >>"$errors"
    fi
  done <<PATHS
$paths
PATHS
  # grep with no files would read its input instead.
  [ "$#" -gt 0 ] || nothing_to_search
else
  cd "$root" || fail "could not enter $root"
  list_command='git ls-files'
  # -z stops git quoting unusual names. A name with a newline in it comes out as
  # two lines, and both are still searched as names.
  paths=$(git ls-files -z 2>>"$errors" | tr '\0' '\n')
  [ -n "$paths" ] || nothing_to_search

  # git grep --cached skips an unmerged file, so its contents can't be vouched for.
  unmerged=$(git ls-files -u 2>>"$errors")
  [ -z "$unmerged" ] || echo "unmerged files in the index: resolve them first" >>"$errors"

  # Git commits a tracked symlink's target text as its content, but git grep only
  # reads regular files, so the targets are read here. One line per link, and the
  # path is everything before the last tab.
  entries=$(git ls-files -s -z 2>>"$errors" | tr '\0' '\n' | grep '^120000 ')
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    oid=${entry#120000 }
    oid=${oid%% *}
    path=${entry#*"$tab"}
    target=$(git cat-file blob "$oid" 2>>"$errors") || echo "could not read link: $path" >>"$errors"
    target=$(printf '%s' "$target" | tr '\n\t' '  ')
    links="$links$path$tab$target
"
  done <<ENTRIES
$entries
ENTRIES
fi

term_line=0
leak_count=0
# read trims the spaces around each term.
while read -r term; do
  term_line=$((term_line + 1))
  [ -n "$term" ] || continue

  if [ -n "${LEAK_SEARCH_ROOT:-}" ]; then
    grep -Fil -- "$term" "$@" >"$work/found" 2>>"$errors"
  else
    git grep --cached --no-color -F -i -l -z -e "$term" >"$work/found" 2>>"$errors"
  fi
  # 0 is a match and 1 is none. Anything else, or anything on stderr, is an error.
  [ "$?" -le 1 ] || echo "the search failed on the term on line $term_line of the term file" >>"$errors"
  in_contents=$(tr '\0' '\n' <"$work/found")
  in_paths=$(printf '%s\n' "$paths" | grep -Fi -- "$term")
  in_links=$(printf '%s' "$links" | grep -Fi -- "$term" | sed "s/${tab}[^${tab}]*\$//")

  hits=$(printf '%s\n%s\n%s\n' "$in_contents" "$in_paths" "$in_links" | sort -u)
  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    leak_count=$((leak_count + 1))
    report_leak "$hit" "$term_line"
  done <<HITS
$hits
HITS
done <<TERMS
$terms
TERMS

if [ -s "$errors" ]; then
  echo "leak test: could not search everything:" >&2
  show_errors
  exit 1
fi
[ "$leak_count" -eq 0 ] || fail "$leak_count leak(s) found"
