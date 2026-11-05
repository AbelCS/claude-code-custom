#!/bin/sh
# assemble_agents <work> <fresh> <project-template>: prints the new AGENTS.md from
# the pieces agents-split.awk wrote to <work>/p and the marks agents-md.sh left:
#   drop.<n>     the piece is left out
#   replace.<n>  the piece, a section's body, becomes the template file named inside
#   insert.<n>   sections to add before piece n; insert.end, at the end
# A fresh file starts with the project template. Inserted sections get a blank line
# before and after them; every other byte is the piece's own. Source this file after
# agents-md.sh's newline and eol; don't run it.

_assemble_ends_blank() { [ -s "$1" ] && [ -z "$(tail -n 1 "$1" | tr -d '\r')" ]; }
_assemble_starts_blank() { [ -s "$1" ] && [ -z "$(head -n 1 "$1" | tr -d '\r')" ]; }

_assemble_insert() { # <file>: inserted sections, after a blank line
  [ -f "$1" ] || return 0
  if [ -s "$_assemble_out" ] && ! _assemble_ends_blank "$_assemble_out"; then
    newline >>"$_assemble_out"
  fi
  cat "$1" >>"$_assemble_out"
  _assemble_gap=true
}

assemble_agents() {
  _assemble_out=$1/assembled
  : >"$_assemble_out"
  [ "$2" = false ] || eol <"$3" >"$_assemble_out"
  _assemble_gap=false
  while read -r _assemble_n _; do
    _assemble_insert "$1/insert.$_assemble_n"
    _assemble_piece=$1/p/$_assemble_n
    [ ! -f "$1/drop.$_assemble_n" ] || continue
    if [ -f "$1/replace.$_assemble_n" ]; then
      eol <"$(cat "$1/replace.$_assemble_n")" >>"$_assemble_out"
      _assemble_gap=false
    elif [ -s "$_assemble_piece" ]; then
      # Text right after inserted sections gets a blank line before it.
      if [ "$_assemble_gap" = true ] && ! _assemble_starts_blank "$_assemble_piece"; then
        newline >>"$_assemble_out"
      fi
      _assemble_gap=false
      cat "$_assemble_piece" >>"$_assemble_out"
    fi
  done <"$1/p/index"
  _assemble_insert "$1/insert.end"
  cat "$_assemble_out"
}
