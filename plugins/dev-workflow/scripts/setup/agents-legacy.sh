#!/bin/sh
# legacy_pieces <work> <src>: decides, for agents-md.sh, what happens to the old
# blocks among the pieces agents-split.awk wrote to <work>/p. Source this file after
# legacy.sh, and with agents-md.sh's report and difference; don't run it.
#
# A piece that matches a published text gets <work>/drop.<n>. A subsection under the
# old heading that doesn't match stays, and so does the heading above it, reported
# as a conflict with its diff from the published text. New sections go where the
# first old block was, before its heading if that stays: <work>/anchor holds that
# piece's number. Report lines go to
# <work>/legacy-report: "legacy:<block>" once for what was replaced, then one line
# for each part kept.

_legacy_heading() { # <piece>: its first line without the #s or trailing space
  head -n 1 "$1" | tr -d '\r' | sed 's/^#* *//; s/[[:space:]]*$//'
}

_legacy_published() { # <version> <first line>: the published file with that heading
  for _lp_file in "$LEGACY_DIR/$1".*.md; do
    if [ "$(head -n 1 "$_lp_file")" = "$2" ]; then
      printf '%s\n' "$_lp_file"
      return 0
    fi
  done
  printf '/dev/null\n'
}

_legacy_named() { # <names> <pattern>: 0 if any line of names matches the pattern
  for _lp_one in $1; do
    # shellcheck disable=SC2254 # The pattern is meant to match.
    case $_lp_one in $2) return 0 ;; esac
  done
  return 1
}

_legacy_kept() { # <version> <piece> <published file>
  report "legacy:$1:$(_legacy_heading "$2")" conflict \
    "$(difference "published project" "$3" "$2")" \
    "edited by the project, so kept" >>"$_lp_work/legacy-kept"
}

legacy_pieces() {
  _lp_work=$1
  : >"$_lp_work/legacy-kept"
  _lp_version=web-5
  _lp_blocks=$(legacy_blocks_in "$2") || return 2
  case $_lp_blocks in *web-6*) _lp_version=web-6 ;; esac
  _lp_head=
  _lp_replaced=false
  while read -r _lp_n _lp_kind _lp_name; do
    _lp_piece=$_lp_work/p/$_lp_n
    case $_lp_kind in
      oldhead | websub | issues)
        _lp_match=$(legacy_match_block "$_lp_piece")
        [ "$?" -ne 2 ] || return 2
        ;;
    esac
    case $_lp_kind in
      oldhead)
        _lp_head=$_lp_n
        if _legacy_named "$_lp_match" 'web-*.0-*'; then
          : >"$_lp_work/drop.$_lp_n"
        else
          _legacy_kept "$_lp_version" "$_lp_piece" "$LEGACY_DIR/$_lp_version.0-heading.md"
        fi
        ;;
      websub)
        if _legacy_named "$_lp_match" 'web-*'; then
          : >"$_lp_work/drop.$_lp_n"
          _lp_replaced=true
        elif [ "$_lp_name" = in ]; then
          rm -f "$_lp_work/drop.$_lp_head"
          _legacy_kept "$_lp_version" "$_lp_piece" \
            "$(_legacy_published "$_lp_version" "$(head -n 1 "$_lp_piece" | tr -d '\r' | sed 's/[[:space:]]*$//')")"
        fi
        ;;
      issues)
        if _legacy_named "$_lp_match" issues; then
          : >"$_lp_work/drop.$_lp_n"
          report legacy:issues update >>"$_lp_work/legacy-report"
        else
          report legacy:issues conflict "$(difference "published project" "$LEGACY_DIR/issues.md" "$_lp_piece")" \
            "edited by the project, so kept" >>"$_lp_work/legacy-report"
        fi
        ;;
    esac
  done <"$_lp_work/p/index"
  if [ "$_lp_replaced" = true ]; then
    report "legacy:$_lp_version" update >>"$_lp_work/legacy-report"
  fi
  cat "$_lp_work/legacy-kept" >>"$_lp_work/legacy-report"
  while read -r _lp_n _lp_kind _lp_name; do
    if [ -f "$_lp_work/drop.$_lp_n" ] || [ "$_lp_kind" = oldhead ]; then
      printf '%s\n' "$_lp_n" >"$_lp_work/anchor"
      break
    fi
  done <"$_lp_work/p/index"
}
