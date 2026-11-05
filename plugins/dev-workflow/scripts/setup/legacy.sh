#!/bin/sh
# Recognises the texts this plugin published before it had managed sections: the old
# rule blocks and CLAUDE.md pointers, kept byte for byte in
# skills/setup/references/legacy/. Source this file; don't run it.
#
# The texts are named so a glob lists them in order, with no index to parse:
#   web-<version>.<n>-<slug>.md  one subsection of the "Web Dev Workflow Rules"
#                                block, n=0 being its heading line
#   issues.md                    the whole "GitHub Issue-Driven Workflow" block
#   pointer-<commit>.md          a CLAUDE.md pointer to AGENTS.md
#
# Texts are compared after legacy_normalise, so CRLF files and trailing spaces still
# match. Nothing else is forgiven.
#
# The folder is found from $0, which must be a script in scripts/setup/. Anything
# else sets LEGACY_DIR first.

if [ -z "${LEGACY_DIR:-}" ]; then
  LEGACY_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/../../skills/setup/references/legacy" 2>/dev/null && pwd)
fi

_legacy_check() { # <file>: 0 if both the file and the published texts can be read
  if [ ! -f "$LEGACY_DIR/issues.md" ]; then
    printf 'legacy.sh: published texts not found in: %s\n' "$LEGACY_DIR" >&2
    return 2
  fi
  if [ ! -f "$1" ] || [ ! -r "$1" ]; then
    printf 'legacy.sh: cannot read: %s\n' "$1" >&2
    return 2
  fi
}

# legacy_normalise: stdin to stdout, with line endings as LF, no whitespace at the end
# of a line, and no blank lines at the end. Every comparison here goes through it.
legacy_normalise() {
  LC_ALL=C awk '
    { sub(/[ \t\r\f\v]+$/, "") }
    $0 == "" { blank++; next }
    { while (blank > 0) { print ""; blank-- } print }
  '
}

# legacy_match_block <file>: prints the name, without .md, of every published text
# the file's whole content equals, one per line. Exits 0 if any matched, 1 if none
# (the project edited it, or it's not an old text), 2 if something can't be read.
legacy_match_block() {
  _legacy_check "$1" || return 2
  _legacy_candidate=$(legacy_normalise <"$1")
  _legacy_status=1
  for _legacy_file in "$LEGACY_DIR"/*.md; do
    if [ "$(legacy_normalise <"$_legacy_file")" = "$_legacy_candidate" ]; then
      _legacy_name=${_legacy_file##*/}
      printf '%s\n' "${_legacy_name%.md}"
      _legacy_status=0
    fi
  done
  return "$_legacy_status"
}

# legacy_blocks_in <file>: prints the old blocks in a file, one id per line, from
# web-5, web-6 and issues. A block counts if its heading is there, even when its
# subsections were edited, or if any of its published subsections is, under any
# heading. It's web-6 if it has a Commit Discipline subsection, or a subsection only
# web-6 published. Text in code fences doesn't count. Exits 2 if it can't read.
legacy_blocks_in() {
  _legacy_check "$1" || return 2
  set -- "$1" "$LEGACY_DIR"/web-*.md
  _legacy_target=$1
  shift
  # The published files come first, then the file on stdin, all normalised alike.
  legacy_normalise <"$_legacy_target" | {
    for _legacy_file in "$@"; do
      printf '\036%s\n' "${_legacy_file##*/}"
      legacy_normalise <"$_legacy_file"
    done
    printf '\036\n'
    cat
  } | LC_ALL=C awk '
    function flush() {
      if (text != "") {
        if (loading) {
          version = substr(name, 5, 1)
          if (version == "5") five[text] = 1; else six[text] = 1
        } else if (text in five) {
          web = web == "" ? "web-5" : web
        } else if (text in six) {
          web = "web-6"
        }
        if (!loading && in_web && sub_heading == "### Commit Discipline") web = "web-6"
      }
      text = ""; blank = ""; sub_heading = ""
    }
    # A marker line in the file itself is just text.
    !target && /^\036/ {
      flush()
      name = substr($0, 2)
      loading = name != ""
      target = !loading
      next
    }
    !loading && /^ ? ? ?(```|~~~)/ { fence = !fence }
    !loading && !fence && /^##? / {
      flush()
      in_web = $0 == "## Web Dev Workflow Rules"
      if (in_web && web == "") web = "web-5"
      if ($0 == "## GitHub Issue-Driven Workflow") issues = 1
      next
    }
    (loading || !fence) && /^### / { flush(); sub_heading = $0; text = $0 "\n"; next }
    text == "" { next }
    $0 == "" { blank = blank "\n"; next }
    { text = text blank $0 "\n"; blank = "" }
    END {
      flush()
      if (web != "") print web
      if (issues) print "issues"
    }
  '
}
