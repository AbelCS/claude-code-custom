# agents-split.awk -v out=<dir> <file>: splits AGENTS.md into pieces for
# agents-md.sh. Each piece goes to <dir>/<n>, byte for byte, and is listed in
# <dir>/index as "<n> <kind> <name>", in file order:
#
#   text     the project's own text
#   begin    a managed section's begin marker line; name is the section
#   body     the text between that section's markers, maybe empty
#   end      its end marker line
#   oldhead  the old "## Web Dev Workflow Rules" heading, up to its first subsection
#   websub   a "### " subsection, up to the next heading or marker; name is "in"
#            under the old heading, "out" anywhere else
#   issues   the old "## GitHub Issue-Driven Workflow" block, subsections and all
#
# Lines are compared without trailing whitespace or CR. Nothing inside a code fence
# is a marker or a heading. A section that begins twice, inside another, or never
# ends, and an end without its begin, are errors: exit 2 with the line.

function piece(kind, name) {
  if (file != "") close(file)
  n++
  file = out "/" n
  printf "" >file
  print n, kind, name >(out "/index")
}

function fail(message) {
  printf "agents-md.sh: AGENTS.md line %d: %s\n", NR, message >"/dev/stderr"
  failed = 1
  exit 2
}

BEGIN { piece("text", "-") }

{
  t = $0
  sub(/[ \t\r\f\v]+$/, "", t)
  if (!fence && t ~ /^<!-- dev-workflow:(begin|end) [a-z0-9][a-z0-9-]* -->$/) {
    split(t, word, " ")
    name = word[3]
    if (word[2] == "dev-workflow:begin") {
      if (body != "") fail("section " name " begins inside section " body)
      if (name in seen) fail("section " name " appears twice")
      seen[name] = 1
      piece("begin", name)
      print >file
      piece("body", name)
      body = name
    } else {
      if (body != name) fail("section " name " ends but never began")
      piece("end", name)
      print >file
      piece("text", "-")
      body = ""
    }
    old = 0
    issues = 0
    next
  }
  if (!fence && body == "") {
    if (t ~ /^##? /) {
      old = t == "## Web Dev Workflow Rules"
      issues = t == "## GitHub Issue-Driven Workflow"
      piece(old ? "oldhead" : issues ? "issues" : "text", "-")
    } else if (!issues && t ~ /^### /) {
      piece("websub", old ? "in" : "out")
    }
  }
  if (t ~ /^ ? ? ?(```|~~~)/) fence = !fence
  print >file
}

END {
  if (failed) exit 2
  if (body != "") fail("section " body " has no end marker")
}
