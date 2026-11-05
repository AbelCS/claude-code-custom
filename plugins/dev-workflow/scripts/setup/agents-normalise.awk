# awk -f agents-normalise.awk: prints a managed section's text in the form its
# fingerprint is taken of, for agents-md.sh. Changes a formatter such as Prettier
# makes, or a person tidying, aren't edits:
#   - line endings and whitespace at the end of a line
#   - blank lines: a run of any length, or none, between two lines is the same
#   - a list item's marker: -, * or +, and any number before . or ), with any spaces
#     after it, read as "- " or "1. "
#   - a table row's padding: the spaces around each cell, a missing last pipe, and
#     the number of dashes in its delimiter row, but not its colons, which align
# In a code fence only the first rule applies, as there every space can matter.

{ sub(/[ \t\r\f\v]+$/, "") }

/^ ? ? ?(```|~~~)/ {
  fence = !fence
  print
  next
}

fence { print; next }

$0 == "" { next }

match($0, /^ *([-*+]|[0-9]+[.)])[ \t]+/) {
  lead = substr($0, 1, RLENGTH)
  indent = lead
  sub(/[^ ].*$/, "", indent)
  $0 = indent (lead ~ /^ *[-*+]/ ? "- " : "1. ") substr($0, RLENGTH + 1)
}

/^ *\|/ {
  row = $0
  sub(/^ *\|/, "", row)
  sub(/\|$/, "", row)
  count = split(row, cells, "|")
  row = "|"
  for (i = 1; i <= count; i++) {
    cell = cells[i]
    gsub(/^[ \t]+|[ \t]+$/, "", cell)
    if (cell ~ /^:?-+:?$/) cell = (cell ~ /^:/ ? ":" : "") "-" (cell ~ /.:$/ ? ":" : "")
    row = row cell "|"
  }
  $0 = row
}

{ print }
