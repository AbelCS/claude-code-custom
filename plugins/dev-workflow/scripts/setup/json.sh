#!/bin/sh
# json_edit <file> <out> <filter> [jq options...]: runs the jq filter on the file's one
# JSON object, or on {} if there's no file, and writes the result to <out> in the
# file's own indent: tabs, or the width of its first indented line, else 2 spaces.
# jq keeps the order of the keys already there, and adds new ones at the end.
# Returns 0 if the result differs from the file in meaning, or there's no file; 1 if
# it doesn't, and then the file is best left as it is; 2 with a message if the file
# isn't one JSON object or can't be read, or the filter fails. Source this file;
# don't run it.

json_edit() {
  _json_file=$1
  _json_out=$2
  _json_filter=$3
  shift 3
  if [ -L "$_json_file" ]; then
    printf '%s is a symlink; not writing through it\n' "$_json_file" >&2
    return 2
  fi
  if [ -e "$_json_file" ]; then
    if ! jq -e -s 'length == 1 and (.[0] | type == "object")' "$_json_file" >/dev/null 2>&1; then
      printf '%s is not valid JSON holding one object: fix it, then run setup again\n' "$_json_file" >&2
      return 2
    fi
    _json_indent=$(awk '
      /^\t/ { print "--tab"; exit }
      /^ +[^ ]/ { match($0, /^ +/); print "--indent " (RLENGTH > 7 ? 7 : RLENGTH); exit }
    ' "$_json_file")
    _json_in=$(cat -- "$_json_file") || return 2
  else
    _json_indent=
    _json_in='{}'
  fi
  # shellcheck disable=SC2086 # The indent is one or two words.
  printf '%s\n' "$_json_in" | jq ${_json_indent:---indent 2} "$@" "$_json_filter" >"$_json_out" || {
    printf 'could not update %s\n' "$_json_file" >&2
    return 2
  }
  [ -e "$_json_file" ] || return 0
  [ "$(printf '%s\n' "$_json_in" | jq -S -c .)" != "$(jq -S -c . "$_json_out")" ]
}
