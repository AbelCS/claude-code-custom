#!/bin/sh
# Reading and writing a project's version in its versionFile, for land's tag-version.sh and
# raise-version.sh, so the two can't read a file differently. Source this file; don't run
# it. Needs jq.
#
# The kinds of file, by name:
#   .json   the top-level "version" field
#   .toml   the version in [project], [package], [tool.poetry] or [workspace.package],
#           in double or single quotes; a version in any other table isn't read
#   other   the first line, trimmed
# The TOML reader works line by line, so a multiline string holding text like a table
# could mislead it: a known limit, in docs/superpowers/specs/2026-11-21-version-tags-design.md.

# The SemVer 2.0.0 grammar, as an extended regular expression for grep -Ex.
version_number='(0|[1-9][0-9]*)'
version_pre_id='(0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)'
version_build_id='[0-9A-Za-z-]+'
# shellcheck disable=SC2034 # The callers read it.
version_semver="$version_number\\.$version_number\\.$version_number(-$version_pre_id(\\.$version_pre_id)*)?(\\+$version_build_id(\\.$version_build_id)*)?"

# version_parse <file name>: prints the version in the file's contents on stdin, or
# nothing.
version_parse() {
  case $1 in
    *.json)
      jq -r 'if type == "object" and (.version | type) == "string" then .version else empty end' 2>/dev/null
      ;;
    *.toml)
      awk -v q="'" '
        /^[[:space:]]*\[/ { table = $0; sub(/#.*/, "", table); gsub(/[[:space:]]/, "", table); next }
        (table == "[project]" || table == "[package]" || table == "[tool.poetry]" || table == "[workspace.package]") &&
          $0 ~ ("^[[:space:]]*version[[:space:]]*=[[:space:]]*[\"" q "]") {
          sub(/^[^=]*=[[:space:]]*/, ""); quote = substr($0, 1, 1); $0 = substr($0, 2)
          sub(quote ".*$", ""); print; exit
        }'
      ;;
    *)
      sed -n '1{s/^[[:space:]]*//;s/[[:space:]]*$//;p;}'
      ;;
  esac
}

# version_write <path> <file name> <old> <new>: changes the version in the file at <path>
# from old to new, in place, touching only the version's own text, then reads it back.
# Returns 1, leaving the file as it was, when the old version isn't where the reader
# finds it, or the file wouldn't read back as new.
version_write() {
  vw_path=$1 vw_name=$2 vw_old=$3 vw_new=$4
  vw_tmp=$vw_path.dw-version.$$
  case $vw_name in
    *.json)
      # The first "version": "<old>". A nested one that comes first is caught by the read
      # back, which then refuses, rather than changing the wrong one.
      # Each "version" key on a line in turn, as compact JSON can hold several.
      awk -v old="$vw_old" -v new="$vw_new" '
        !done {
          seen = 0
          while (!done && match(substr($0, seen + 1), /"version"[[:space:]]*:[[:space:]]*"/)) {
            start = seen + RSTART + RLENGTH
            if (substr($0, start, length(old) + 1) == old "\"") {
              $0 = substr($0, 1, start - 1) new substr($0, start + length(old)); done = 1
            }
            seen = start - 1
          }
        }
        { print }' "$vw_path" >"$vw_tmp"
      ;;
    *.toml)
      awk -v q="'" -v old="$vw_old" -v new="$vw_new" '
        /^[[:space:]]*\[/ { table = $0; sub(/#.*/, "", table); gsub(/[[:space:]]/, "", table) }
        !done && (table == "[project]" || table == "[package]" || table == "[tool.poetry]" || table == "[workspace.package]") &&
          match($0, "^[[:space:]]*version[[:space:]]*=[[:space:]]*[\"" q "]") {
          quote = substr($0, RLENGTH, 1)
          if (substr($0, RLENGTH + 1, length(old) + 1) == old quote) {
            $0 = substr($0, 1, RLENGTH) new substr($0, RLENGTH + 1 + length(old)); done = 1
          }
        }
        { print }' "$vw_path" >"$vw_tmp"
      ;;
    *)
      # Only the version itself, so spaces and a carriage return around it stay.
      awk -v old="$vw_old" -v new="$vw_new" '
        NR == 1 {
          line = $0; sub(/^[[:space:]]*/, "", line); sub(/[[:space:]]*$/, "", line)
          if (line == old) { at = index($0, old); $0 = substr($0, 1, at - 1) new substr($0, at + length(old)) }
        }
        { print }' "$vw_path" >"$vw_tmp"
      ;;
  esac || {
    rm -f "$vw_tmp"
    return 1
  }
  if [ "$(version_parse "$vw_name" <"$vw_tmp")" != "$vw_new" ]; then
    rm -f "$vw_tmp"
    return 1
  fi
  # awk ends every line with a newline: a file without a final one keeps none.
  if [ -s "$vw_path" ] && [ -n "$(tail -c 1 "$vw_path")" ]; then
    if ! { vw_text=$(cat "$vw_tmp") && printf '%s' "$vw_text" >"$vw_tmp"; }; then
      rm -f "$vw_tmp"
      return 1
    fi
  fi
  # Into a copy that keeps the original's mode, then renamed over it, so a failure part
  # way leaves the original whole.
  vw_copy=$vw_path.dw-version-copy.$$
  if ! { cp -p "$vw_path" "$vw_copy" && cat "$vw_tmp" >"$vw_copy" && mv -f "$vw_copy" "$vw_path"; }; then
    rm -f "$vw_tmp" "$vw_copy"
    return 1
  fi
  rm -f "$vw_tmp"
}
