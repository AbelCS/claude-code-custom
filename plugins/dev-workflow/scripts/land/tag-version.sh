#!/bin/sh
# Usage: tag-version.sh <root> [<commit>]
#
# Tags the project's version as of <commit>, the merge land just made, or as of origin's
# default branch without one. Every version is a git tag holding the bare version, like
# 1.4.0. Prints one line:
#   tagged <version> <commit>   the tag was missing on origin: created and pushed
#   done <version> <commit>     the tag was already there, which is what most merges find
#   skip release-please: ...    release-please tags versions in this project
#   skip no-version-file: ...   the project file names no versionFile
#
# <commit> has to be on origin's default branch, which is fetched first. Its own project
# file names versionFile, a path from the root, and its own tree says whether
# release-please is set up: a later merge may have changed either. The version is read
# from that file as committed there: a .json file's "version" field, a .toml file's
# version in [project], [package], [tool.poetry] or [workspace.package], and any other
# file's first line. It must follow SemVer 2.0.0's grammar, with no v, such as 1.4.0 or
# 2.0.0-rc.1, and be a name git allows for a tag.
#
# The tag goes on the commit that set that version: walking back along the default
# branch's own line, first parents only, through the commits that touched the file, the
# oldest one in the run still holding it. So it doesn't matter how many merges came
# after. A shallow clone can't show that, so it stops, and so does a project file whose
# defaultBranch isn't origin's. A tag already there, locally or on origin, is never
# moved: on another commit, it's reported.
#
# Exits 1 when the version can't be tagged, saying why, and 2 on bad usage or a folder
# that isn't a set-up project.

die() {
  printf 'tag-version.sh: %s\n' "$*" >&2
  exit 2
}

fail() {
  printf 'tag-version.sh: %s\n' "$*" >&2
  exit 1
}

[ "$#" -eq 1 ] || [ "$#" -eq 2 ] || die "usage: tag-version.sh <root> [<commit>]"
for tool in git jq; do
  command -v "$tool" >/dev/null 2>&1 || die "missing required tool: $tool"
done
[ -d "$1" ] || die "not a folder: $1"
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE

root=$1
project=$root/.claude/dev-workflow.json
[ -f "$project" ] || die "no project file at $project: run the setup skill first"

default=$(jq -r '.defaultBranch // "main"' "$project") || die "cannot read $project"

# shellcheck source=plugins/dev-workflow/scripts/lib/version-file.sh
. "$(dirname -- "$0")/../lib/version-file.sh"

g() {
  git -C "$root" "$@"
}

# Only the refs named: no other tags, and no pruning, which could remove a local tag
# before it's checked.
fetch() {
  g -c fetch.prune=false -c fetch.pruneTags=false fetch -q --no-tags origin "$@"
}

[ "$(g rev-parse --is-shallow-repository)" = false ] ||
  fail "this is a shallow clone, which can't show the commit that set the version: run git fetch --unshallow, then try again"
# A project file that names another branch than origin's own would tag the wrong line.
head=$(g ls-remote --symref origin HEAD) || fail "could not read origin's default branch"
head=$(printf '%s\n' "$head" | awk '$1 == "ref:" && $3 == "HEAD" && sub(/^refs\/heads\//, "", $2) { print $2 }')
if [ -n "$head" ] && [ "$head" != "$default" ]; then
  fail "origin's default branch is $head, but the project file says $default: run git remote set-head origin --auto and the setup skill to update it, then try again"
fi
fetch "+refs/heads/$default:refs/remotes/origin/$default" ||
  fail "could not fetch $default from origin"
tip=$(g rev-parse -q --verify "refs/remotes/origin/$default^{commit}") ||
  fail "origin has no $default branch"
if [ "$#" -eq 2 ]; then
  start=$(g rev-parse -q --verify "$2^{commit}") || fail "not a commit: $2"
  g merge-base --is-ancestor "$start" "$tip" || fail "$2 isn't on origin/$default, so it isn't a merge to tag"
else
  start=$tip
fi

# The settings as they were in that commit: a later merge may have changed them.
if g cat-file -e "$start:release-please-config.json" 2>/dev/null; then
  echo 'skip release-please: its second run tags each release'
  exit 0
fi
file=$(g show "$start:.claude/dev-workflow.json" 2>/dev/null | jq -r '.versionFile // empty' 2>/dev/null)
if [ -z "$file" ]; then
  echo 'skip no-version-file: versions aren'"'"'t tagged here until setup records versionFile, the file that holds the version'
  exit 0
fi

# version_at <commit>: prints the version the file holds there, or nothing.
version_at() {
  content=$(g show "$1:$file" 2>/dev/null) || return 1
  printf '%s\n' "$content" | version_parse "$file"
}

g cat-file -e "$start:$file" 2>/dev/null || fail "$file isn't on origin/$default"
version=$(version_at "$start")
if ! printf '%s\n' "$version" | grep -Eqx "$version_semver"; then
  fail "$file holds \"$version\", which isn't a bare SemVer version such as 1.4.0"
fi
git check-ref-format "refs/tags/$version" ||
  fail "$file holds \"$version\", which is SemVer, but git doesn't allow it as a tag name"

target=
for commit in $(g rev-list --first-parent "$start" -- ":(literal)$file"); do
  [ "$(version_at "$commit")" = "$version" ] || break
  target=$commit
done
[ -n "$target" ] || fail "could not find the commit that set $version in $file"

remote_tags=$(g ls-remote --tags origin) || fail "could not list origin's tags"
remote=$(printf '%s\n' "$remote_tags" | awk -v ref="refs/tags/$version" '
  $2 == ref { sha = $1 } $2 == ref "^{}" { peeled = $1 }
  END { print (peeled != "" ? peeled : sha) }')
local=$(g rev-parse -q --verify "refs/tags/$version^{commit}")

if [ -n "$local" ] && [ "$local" != "$target" ]; then
  fail "the tag $version here is on $local, not on $target, which set $version in $file: it's left as it is, for a person to sort out"
fi

if [ -n "$remote" ]; then
  if [ "$remote" != "$target" ]; then
    fail "origin's tag $version is on $remote, not on $target, which set $version in $file: it's left as it is, for a person to sort out"
  fi
  if [ -z "$local" ]; then
    fetch "refs/tags/$version:refs/tags/$version" || fail "could not fetch the tag $version"
  fi
  echo "done $version $target"
  exit 0
fi

if [ -z "$local" ]; then
  g tag -a "$version" -m "$version" "$target" || fail "could not create the tag $version"
fi
g push -q origin "refs/tags/$version" || fail "could not push the tag $version"
echo "tagged $version $target"
