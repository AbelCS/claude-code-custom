#!/bin/sh
# The readiness review's entry in docs/readiness.md, for raise-version.sh's gate and the
# readiness skill's check-entry.sh, so the two read one form. Source this file; don't run
# it.
#
# An entry is a section headed exactly "## <version>, <YYYY-MM-DD>". The readiness skill
# writes the heading only once every item on its checklist is done, not applicable or
# accepted.

# readiness_has_entry <version>: whether the text on stdin holds that version's entry.
readiness_has_entry() {
  re_version=$(printf '%s' "$1" | sed 's/[.+]/\\&/g')
  grep -Eqx -- "## $re_version, [0-9]{4}-[0-9]{2}-[0-9]{2}"
}

# readiness_is_stable <version>: whether it's 1.0.0 or above and not a pre-release, the
# versions the gate is for.
readiness_is_stable() {
  # Build metadata, after a +, can hold a dash, and isn't a pre-release.
  case ${1%%+*} in
    0.* | *-*) return 1 ;;
  esac
}

# readiness_before_stable <version>: whether it comes before 1.0.0 in SemVer's order: a
# 0.x, or a pre-release of 1.0.0.
readiness_before_stable() {
  case ${1%%+*} in
    0.* | 1.0.0-*) return 0 ;;
  esac
  return 1
}
