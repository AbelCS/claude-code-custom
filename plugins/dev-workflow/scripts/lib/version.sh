#!/bin/sh
# Comparing versions, for hook-session-start.sh and setup/tools.sh. Source this file;
# don't run it. Uses the shell alone.

# Sets version_parts to the three numbers of a version, ignoring a pre-release or build
# part, with missing numbers as 0. Returns 1 if it isn't a version, which includes numbers
# too long for the shell to compare.
read_version() {
  rv_numbers=${1%%[-+]*}
  case $rv_numbers in
    '' | .* | *. | *..* | *[!0-9.]* | *[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]*) return 1 ;;
  esac
  rv_ifs=$IFS
  IFS=.
  # shellcheck disable=SC2086 # Split on the dots.
  set -- $rv_numbers 0 0
  IFS=$rv_ifs
  # shellcheck disable=SC2034 # The caller reads it.
  version_parts="$1 $2 $3"
}

# version_is_older <a> <b>: both already through read_version, as "1 2 3".
version_is_older() {
  # shellcheck disable=SC2086 # Three numbers.
  set -- $1 $2
  # By test rather than arithmetic, which would read a leading zero as octal.
  [ "$1" -lt "$4" ] && return 0
  [ "$1" -gt "$4" ] && return 1
  [ "$2" -lt "$5" ] && return 0
  [ "$2" -gt "$5" ] && return 1
  [ "$3" -lt "$6" ]
}
