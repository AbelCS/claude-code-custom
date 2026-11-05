#!/bin/sh
# Part of hook-bash.sh. Source this file; don't run it.

# walk_flags <long flags taking a value> <letters taking a value> <letters that can only
# have a value attached> <function> <words...>
#
# Reads words the way git and gh do, calling the function for each thing found:
#   <function> <flag> <value>   a flag with a value, in any form: --a=1, --a 1, -a1, -a 1
#   <function> <flag>           a flag without one, also from inside -abc
#   <function> "" <word>        anything else, and everything after --
# So a value is never taken for a flag. The function must not use wf_ names.
walk_flags() {
  wf_long=" $1 "
  wf_letters=$2
  wf_attached=$3
  wf_on=$4
  shift 4
  while [ "$#" -gt 0 ]; do
    wf_word=$1
    shift
    case $wf_word in
      --)
        for wf_word in "$@"; do
          "$wf_on" "" "$wf_word"
        done
        return 0
        ;;
      --*=*) "$wf_on" "${wf_word%%=*}" "${wf_word#*=}" ;;
      --*)
        case $wf_long in
          *" $wf_word "*)
            "$wf_on" "$wf_word" "${1-}"
            [ "$#" -eq 0 ] || shift
            ;;
          *) "$wf_on" "$wf_word" ;;
        esac
        ;;
      -?*)
        wf_rest=${wf_word#-}
        while [ -n "$wf_rest" ]; do
          wf_letter=${wf_rest%"${wf_rest#?}"}
          wf_rest=${wf_rest#?}
          case $wf_letters in
            *"$wf_letter"*)
              if [ -n "$wf_rest" ]; then
                "$wf_on" "-$wf_letter" "${wf_rest#=}"
              else
                "$wf_on" "-$wf_letter" "${1-}"
                [ "$#" -eq 0 ] || shift
              fi
              wf_rest=
              ;;
            *)
              case $wf_attached in
                *"$wf_letter"*) wf_rest= ;;
                *) "$wf_on" "-$wf_letter" ;;
              esac
              ;;
          esac
        done
        ;;
      *) "$wf_on" "" "$wf_word" ;;
    esac
  done
}
