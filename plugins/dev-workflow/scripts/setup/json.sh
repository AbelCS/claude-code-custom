#!/bin/sh
# json_edit <file> <out> <filter> [jq options...]: runs the jq filter on the file's one
# JSON object, or on {} if there's no file, and writes the result to <out> in the
# file's own indent: tabs, or the width of its first indented line, else 2 spaces.
# jq keeps the order of the keys already there, and adds new ones at the end.
# Returns 0 if the result differs from the file in meaning, or there's no file; 1 if
# it doesn't, and then the file is best left as it is; 2 with a message if the file
# isn't one JSON object or can't be read, or the filter fails.
#
# json_format [indent] [file name]: prints the JSON on stdin the way Prettier prints it
# by default, with json-format.jq, indented by the given text, two spaces if none. For
# package.json, package-lock.json and composer.json, that's as JSON.stringify prints.
# json_edit writes through it.
#
# json_indent <file>: prints the file's indent, as json_edit keeps it, or nothing.
#
# Source this file, with $here set to this folder; don't run it.

# shellcheck disable=SC2154 # The script sourcing this sets here.

json_format() {
  case ${2##*/} in
    package.json | package-lock.json | composer.json) _json_stringify=true ;;
    *) _json_stringify=false ;;
  esac
  jq -r --arg step "${1:-  }" --argjson stringify "$_json_stringify" -f "$here/json-format.jq"
}

json_indent() {
  awk '
    /^\t/ { print "\t"; exit }
    /^ +[^ ]/ { match($0, /^ +/); print substr($0, 1, RLENGTH > 7 ? 7 : RLENGTH); exit }
  ' "$1"
}

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
    _json_indent=$(json_indent "$_json_file")
    _json_in=$(cat -- "$_json_file") || return 2
  else
    _json_indent=
    _json_in='{}'
  fi
  # The filter's own failure is the one that counts, not the formatter's after it.
  if ! printf '%s\n' "$_json_in" | jq -c "$@" "$_json_filter" >"$_json_out.value" ||
    ! json_format "${_json_indent:-  }" "$_json_file" <"$_json_out.value" >"$_json_out"; then
    rm -f -- "$_json_out.value"
    printf 'could not update %s\n' "$_json_file" >&2
    return 2
  fi
  rm -f -- "$_json_out.value"
  [ -e "$_json_file" ] || return 0
  [ "$(printf '%s\n' "$_json_in" | jq -S -c .)" != "$(jq -S -c . "$_json_out")" ]
}
