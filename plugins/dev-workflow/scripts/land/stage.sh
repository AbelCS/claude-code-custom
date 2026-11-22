#!/bin/sh
# Usage: stage.sh <root>
#
# The project's stage, for land, which applies stricter checks from 1.0.0. Prints one line:
#   early <version>    before 1.0.0, in SemVer's order: a 0.x, or a 1.0.0 candidate
#   stable <version>   1.0.0 or above
#   stable unknown     no version to read: the stricter rules, since it can't tell
#
# The version is the one in versionFile on origin's default branch, where origin's own
# project file says it is, fetched first, as that's what the project has released. A
# version file this branch adds is read from the branch, as origin has none yet. When
# origin can't be reached, the stage is unknown. Exits 2 on bad usage or a folder that isn't a set-up
# project.

die() {
  printf 'stage.sh: %s\n' "$*" >&2
  exit 2
}

[ "$#" -eq 1 ] || die "usage: stage.sh <root>"
for tool in git jq; do
  command -v "$tool" >/dev/null 2>&1 || die "missing required tool: $tool"
done
[ -d "$1" ] || die "not a folder: $1"
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE

root=$1
project=$root/.claude/dev-workflow.json
[ -f "$project" ] || die "no project file at $project: run the setup skill first"
here=$(dirname -- "$0")
# shellcheck source=plugins/dev-workflow/scripts/lib/version-file.sh
. "$here/../lib/version-file.sh"
# shellcheck source=plugins/dev-workflow/scripts/lib/readiness.sh
. "$here/../lib/readiness.sh"

g() {
  git -C "$root" "$@"
}

file=$(jq -r '.versionFile // empty' "$project" 2>/dev/null)
default=$(jq -r '.defaultBranch // "main"' "$project" 2>/dev/null)
version=
# An old copy of origin can't vouch for the stage, so a failed fetch leaves it unknown.
if [ -n "$file" ] && g -c fetch.prune=false -c fetch.pruneTags=false fetch -q --no-tags origin \
  "+refs/heads/$default:refs/remotes/origin/$default" 2>/dev/null; then
  base=refs/remotes/origin/$default
  # Where origin's own project file says its version is: the file may move on a branch.
  base_file=$(g show "$base:.claude/dev-workflow.json" 2>/dev/null | jq -r '.versionFile // empty | strings' 2>/dev/null)
  [ -n "$base_file" ] || base_file=$file
  if g cat-file -e "$base:$base_file" 2>/dev/null; then
    version=$(g show "$base:$base_file" | version_parse "$base_file")
  elif [ -f "$root/$file" ]; then
    version=$(version_parse "$file" <"$root/$file")
  fi
fi

if ! printf '%s\n' "$version" | grep -Eqx "$version_semver"; then
  echo 'stable unknown'
elif readiness_before_stable "$version"; then
  echo "early $version"
else
  echo "stable $version"
fi
