#!/bin/sh
# Usage: check-entry.sh <root> <version>
#
# For the readiness skill, after writing its entry: whether <root>/docs/readiness.md holds
# the entry for <version>, in the form land's gate reads, through scripts/lib/readiness.sh.
# Prints the heading it looked for when it isn't there.
#
# Exits 0 when the entry is there, 1 when it isn't, and 2 on bad usage.

die() {
  printf 'check-entry.sh: %s\n' "$*" >&2
  exit 2
}

[ "$#" -eq 2 ] || die "usage: check-entry.sh <root> <version>"
[ -d "$1" ] || die "not a folder: $1"
here=$(dirname -- "$0")
# shellcheck source=plugins/dev-workflow/scripts/lib/version-file.sh
. "$here/../lib/version-file.sh"
# shellcheck source=plugins/dev-workflow/scripts/lib/readiness.sh
. "$here/../lib/readiness.sh"
printf '%s\n' "$2" | grep -Eqx "$version_semver" || die "not a bare SemVer version: $2"

file=$1/docs/readiness.md
if [ -f "$file" ] && readiness_has_entry "$2" <"$file"; then
  echo "found: the entry for $2 in docs/readiness.md"
  exit 0
fi
printf 'check-entry.sh: docs/readiness.md has no entry headed "## %s, YYYY-MM-DD"\n' "$2" >&2
exit 1
