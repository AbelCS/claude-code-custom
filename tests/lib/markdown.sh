#!/bin/sh
# markdown_form <file>: prints each place the file isn't in the form Prettier keeps
# Markdown by default, one a line, and nothing if it is. Source this file after
# assert.sh; don't run it. It checks what setup writes, not all of Markdown:
#   - no whitespace at the end of a line, and one newline at the end of the file
#   - no two blank lines together, and none at the start or end
#   - a blank line before and after each heading, HTML comment line and code fence
#   - list items marked "-", not "*" or "+"
#   - every row of a table with its pipes in the same columns, as Prettier pads cells
# The fixtures test runs Prettier itself on setup's output.

markdown_form() {
  awk '
    function problem(what) { printf "%s line %d: %s\n", FILENAME, FNR, what; bad = 1 }
    function block(line) { return line ~ /^#+ / || line ~ /^<!--.*-->$/ }
    function pipes(line,    i, out) {
      out = ""
      for (i = 1; i <= length(line); i++) if (substr(line, i, 1) == "|") out = out i ","
      return out
    }
    {
      if ($0 ~ /[ \t\r]$/) problem("whitespace at the end")
      is_fence = $0 ~ /^ ? ? ?(```|~~~)/
      if (fence && !is_fence) { prev = $0; prev_kind = "code"; next }
      if ($0 == "") {
        if (FNR == 1) problem("a blank first line")
        if (prev == "" && FNR > 1) problem("two blank lines together")
      }
      kind = is_fence ? (fence ? "close" : "open") : block($0) ? "block" : $0 == "" ? "blank" : "text"
      if ((kind == "block" || kind == "open") && FNR > 1 && prev != "") problem("no blank line before this")
      if ((prev_kind == "block" || prev_kind == "close") && $0 != "") problem("no blank line after the line before")
      if (!fence && $0 ~ /^ *[*+][ \t]/) problem("a list item not marked with -")
      if (!fence && $0 ~ /^ *\|/) {
        if (in_table && pipes($0) != columns) problem("a table row not padded like the one before")
        columns = pipes($0)
        in_table = 1
      } else in_table = 0
      if (is_fence) fence = !fence
      prev = $0
      prev_kind = kind
    }
    END {
      if (prev == "") problem("a blank last line")
      exit bad
    }
  ' "$1"
  # A file whose last line has no newline.
  [ ! -s "$1" ] || [ "$(tail -c 1 "$1" | od -An -c | tr -d ' ')" = '\n' ] || printf '%s: no newline at the end\n' "$1"
}

# assert_markdown_form <file>
assert_markdown_form() {
  _md_problems=$(markdown_form "$1")
  [ -z "$_md_problems" ] || _assert_fail "not in the form Prettier keeps:
$_md_problems"
}
