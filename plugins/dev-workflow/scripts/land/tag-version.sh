#!/bin/sh
# Usage: tag-version.sh <root> [<commit>]
#
# Tags the project's version as of <commit>, the merge land just made, or as of origin's
# default branch without one, for land after a merge. Every version is a git
# tag holding the bare version, like 1.4.0. Prints one line:
#   tagged <version> <commit>   created the tag on that commit, and pushed it
#   done <version> <commit>     the tag was already there, which is what most merges find
#   skip release-please: ...    release-please tags versions in this project
#   skip no-version-file: ...   the project file names no versionFile
#
# The version is read from versionFile, a path from the root in .claude/dev-workflow.json,
# as committed in <commit>, which has to be on origin's default branch, fetched first: a
# .json file's "version" field, a .toml file's version in [project], [package],
# [tool.poetry] or [workspace.package], and any other file's first line. It must be a bare SemVer version,
# such as 1.4.0 or 2.0.0-rc.1, with no v.
#
# The tag goes on the commit that set that version: walking back along the default
# branch's own line, first parents only, through the commits that touched the file, the
# oldest one in the run still holding it. So it doesn't matter how many merges came
# after. A shallow clone can't show that, so it stops, and so does a project file whose
# defaultBranch isn't origin's. The version follows SemVer 2.0.0's grammar, and has to be
# a name git allows for a tag. A tag already there, locally or on origin, is never
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

if [ -e "$root/release-please-config.json" ]; then
  echo 'skip release-please: its second run tags each release'
  exit 0
fi

file=$(jq -r '.versionFile // empty' "$project") || die "cannot read $project"
default=$(jq -r '.defaultBranch // "main"' "$project") || die "cannot read $project"
if [ -z "$file" ]; then
  echo 'skip no-version-file: versions aren'"'"'t tagged here until setup records versionFile, the file that holds the version'
  exit 0
fi

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
  fail "origin's default branch is $head, but the project file says $default: run the setup skill to update it, then try again"
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

# version_at <commit>: prints the version the file holds there, or nothing.
version_at() {
  content=$(g show "$1:$file" 2>/dev/null) || return 1
  case $file in
    *.json)
      printf '%s\n' "$content" |
        jq -r 'if type == "object" and (.version | type) == "string" then .version else empty end' 2>/dev/null
      ;;
    *.toml)
      printf '%s\n' "$content" | awk -v q="'" '
        /^[[:space:]]*\[/ { table = $0; sub(/#.*/, "", table); gsub(/[[:space:]]/, "", table); next }
        (table == "[project]" || table == "[package]" || table == "[tool.poetry]" || table == "[workspace.package]") &&
          $0 ~ ("^[[:space:]]*version[[:space:]]*=[[:space:]]*[\"" q "]") {
          sub(/^[^=]*=[[:space:]]*/, ""); quote = substr($0, 1, 1); $0 = substr($0, 2)
          sub(quote ".*$", ""); print; exit
        }'
      ;;
    *)
      printf '%s\n' "$content" | sed -n '1{s/^[[:space:]]*//;s/[[:space:]]*$//;p;}'
      ;;
  esac
}

g cat-file -e "$start:$file" 2>/dev/null || fail "$file isn't on origin/$default"
version=$(version_at "$start")
# SemVer 2.0.0's own grammar: numbers without leading zeros, and a prerelease part whose
# identifiers are numbers without them, or hold a letter or a dash.
number='(0|[1-9][0-9]*)'
pre_id='(0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)'
build_id='[0-9A-Za-z-]+'
semver="$number\\.$number\\.$number(-$pre_id(\\.$pre_id)*)?(\\+$build_id(\\.$build_id)*)?"
if ! printf '%s\n' "$version" | grep -Eqx "$semver"; then
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
