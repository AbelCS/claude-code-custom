#!/bin/sh
# agents-md.sh's text helpers, for the file's line endings, which $crlf says, in the
# temp folder $work. Source this file, from agents-md.sh, which has $here and
# legacy_normalise; don't run it.
#
#   newline                       one line ending
#   eol                           stdin with the file's line endings
#   section <template>            the text between a section's markers, as setup
#                                 writes it: a blank line, the template, a blank line
#   fingerprint <file>            the hash a section's text is compared by
#   report <section> <action> [diff] [detail]
#                                 one JSON line of agents-md.sh's output
#   difference <labels> <template> <file>
#                                 a unified diff of their normalised text

# shellcheck disable=SC2154 # agents-md.sh sets crlf and work.

newline() { if [ "$crlf" = true ]; then printf '\r\n'; else printf '\n'; fi; }
eol() { if [ "$crlf" = true ]; then awk '{ printf "%s\r\n", $0 }'; else cat; fi; }

fingerprint() { awk -f "$here/agents-normalise.awk" "$1" >"$work/norm" && sh "$here/ledger.sh" hash "$work/norm"; }

section() { newline && eol <"$1" && newline; }

report() { # <section> <action> [diff] [detail]
  jq -cn --arg s "$1" --arg a "$2" --arg d "${3:-}" --arg t "${4:-}" \
    '{section: $s, action: $a} + (if $d == "" then {} else {diff: $d} end) +
     (if $t == "" then {} else {detail: $t} end)'
}

difference() { # <labels> <template> <file>
  section "$2" | legacy_normalise >"$work/diff-a"
  legacy_normalise <"$3" >"$work/diff-b"
  printf -- '--- %s\n+++ %s\n' "${1%% *}" "${1#* }"
  diff -u "$work/diff-a" "$work/diff-b" | sed '1,2d'
}
