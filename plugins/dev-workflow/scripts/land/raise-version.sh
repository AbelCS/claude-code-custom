#!/bin/sh
# Usage: raise-version.sh <root> <title>
#
# Raises the project's version for a pull request about to merge, for land, in a project
# without release-please. <title> is the pull request's title, a Conventional Commit, which
# becomes the squash commit's subject. Prints one line:
#   raised <old> <new>          wrote the new version, and committed it on this branch
#   unchanged <type>: ...       a type that changes no version, such as docs or chore
#   skip <reason>: ...          release-please, no versionFile, a pre-release version, a
#                               first version file, or a version already raised in this
#                               branch, which, from below 1.0.0 to 1.0.0 or above, needs
#                               its entry in docs/readiness.md
#
# The bump is release-please's: feat raises the minor, fix and perf the patch, and a ! before
# the colon, on any type, the major. Before 1.0.0 it's one step lower: a breaking change
# raises the minor, and a feature the patch. The old version is the one on origin's default
# branch, fetched first, which the branch must already hold, so two branches can't claim
# the same number: if it has moved on, this says to merge it in first. The new version is
# written into versionFile in place, by scripts/lib/version-file.sh, as one commit,
# "chore: release <new> (#<issue>)", the issue from the branch's name.
#
# Exits 1 when it can't raise the version, saying why, and 2 on bad usage or a folder that
# isn't a set-up project.

die() {
  printf 'raise-version.sh: %s\n' "$*" >&2
  exit 2
}

fail() {
  printf 'raise-version.sh: %s\n' "$*" >&2
  exit 1
}

[ "$#" -eq 2 ] || die "usage: raise-version.sh <root> <title>"
for tool in git jq; do
  command -v "$tool" >/dev/null 2>&1 || die "missing required tool: $tool"
done
[ -d "$1" ] || die "not a folder: $1"
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE

root=$1
title=$2
project=$root/.claude/dev-workflow.json
[ -f "$project" ] || die "no project file at $project: run the setup skill first"

here=$(dirname -- "$0")
# shellcheck source=plugins/dev-workflow/scripts/lib/version-file.sh
. "$here/../lib/version-file.sh"
# shellcheck source=plugins/dev-workflow/scripts/lib/version.sh
. "$here/../lib/version.sh"
# shellcheck source=plugins/dev-workflow/scripts/lib/readiness.sh
. "$here/../lib/readiness.sh"

g() {
  git -C "$root" "$@"
}

default=$(jq -r '.defaultBranch // "main"' "$project") || die "cannot read $project"
branch=$(g symbolic-ref -q --short HEAD) || fail "not on a branch: raise the version on the pull request's branch"
[ "$branch" != "$default" ] || fail "this is $default: raise the version on the pull request's branch"

# The type, and whether a ! marks a breaking change, from <type>[(<scope>)][!]: <subject>.
parsed=$(printf '%s\n' "$title" | awk '
  NR == 1 && match($0, /^[a-z]+(\([^)]*\))?!?: [^ ]/) {
    head = substr($0, 1, RLENGTH - 3); bang = (substr(head, length(head)) == "!")
    sub(/[(!].*$/, "", head); print head, (bang ? "!" : "-")
  }')
[ -n "$parsed" ] || fail "the title isn't a Conventional Commit, like feat: add search (#12): $title"
type=${parsed% *}
bang=${parsed#* }

# As committed: a config left lying about uncommitted won't be in the merge.
if g cat-file -e "HEAD:release-please-config.json" 2>/dev/null; then
  echo 'skip release-please: it raises the version when a release is cut'
  exit 0
fi
file=$(jq -r '.versionFile // empty' "$project") || die "cannot read $project"
if [ -z "$file" ]; then
  echo 'skip no-version-file: the project file names no versionFile, so there is no version to raise'
  exit 0
fi

[ -z "$(g status --porcelain --untracked-files=no)" ] ||
  fail "there are uncommitted changes, which would go into the release commit: commit or stash them first"

g -c fetch.prune=false -c fetch.pruneTags=false fetch -q --no-tags origin \
  "+refs/heads/$default:refs/remotes/origin/$default" || fail "could not fetch $default from origin"
base=refs/remotes/origin/$default
g merge-base --is-ancestor "$base" HEAD ||
  fail "origin/$default has moved on since this branch: bring it in with git merge origin/$default, then try again"

[ -f "$root/$file" ] || fail "$file is missing from this branch"
current=$(version_parse "$file" <"$root/$file")
printf '%s\n' "$current" | grep -Eqx "$version_semver" ||
  fail "$file holds \"$current\", which isn't a bare SemVer version such as 1.4.0"

# A version file this pull request adds: its version is the first, tagged after the merge.
if ! g cat-file -e "$base:$file" 2>/dev/null; then
  echo "skip first-version: $current is the first version in $file, and is tagged after the merge"
  exit 0
fi
old=$(g show "$base:$file" | version_parse "$file")
printf '%s\n' "$old" | grep -Eqx "$version_semver" ||
  fail "$file on origin/$default holds \"$old\", which isn't a bare SemVer version such as 1.4.0"

# Raised by hand already: kept, as long as it's higher. A pre-release of the same numbers
# comes before the release itself.
if [ "$current" != "$old" ]; then
  read_version "$current" && current_parts=$version_parts
  read_version "$old" && old_parts=$version_parts
  if version_is_older "$current_parts" "$old_parts" ||
    { [ "$current_parts" = "$old_parts" ] && case $current in *-*) true ;; *) false ;; esac; }; then
    fail "$file holds $current, which is lower than $old on origin/$default: raise it, or put back $old and run this again"
  fi
  # Going stable is a deliberate step, and it passes the readiness review first: its
  # entry in docs/readiness.md, as committed on this branch. A candidate such as
  # 1.0.0-rc.1 still comes before 1.0.0, so it isn't gated, and the step from it is.
  if readiness_before_stable "$old" && readiness_is_stable "$current"; then
    if ! g show "HEAD:docs/readiness.md" 2>/dev/null | readiness_has_entry "$current"; then
      fail "$current is the first stable version, which needs its readiness review first: run /dev-workflow:readiness, which records it in docs/readiness.md"
    fi
  fi
  echo "skip already-raised: $current, against $old on origin/$default"
  exit 0
fi
case $old in
  *[-+]*)
    echo "skip pre-release: $old is a pre-release, and what comes after it is a person's call"
    exit 0
    ;;
esac

if [ "$bang" = '!' ]; then
  bump='major'
else
  case $type in
    feat) bump='minor' ;;
    fix | perf) bump='patch' ;;
    *)
      echo "unchanged $type: a $type changes no version"
      exit 0
      ;;
  esac
fi

major=${old%%.*}
rest=${old#*.}
minor=${rest%%.*}
patch=${rest#*.}
if [ "$major" = 0 ]; then
  case $bump in
    major) bump='minor' ;;
    minor) bump='patch' ;;
  esac
fi
case $bump in
  major) new=$((major + 1)).0.0 ;;
  minor) new=$major.$((minor + 1)).0 ;;
  patch) new=$major.$minor.$((patch + 1)) ;;
esac

version_write "$root/$file" "$file" "$old" "$new" ||
  fail "could not write $new into $file: its version isn't where it's read from, so it's left as it was"

subject="chore: release $new"
issue=${branch#*/}
issue=${issue%%-*}
case $branch in
  */*-*) case $issue in '' | *[!0-9]*) ;; *) subject="$subject (#$issue)" ;; esac ;;
esac
# Only the version file goes in, and a refused commit leaves it as it was.
if ! g commit -q -m "$subject" -- ":(literal)$file"; then
  g restore --staged --worktree -- ":(literal)$file" 2>/dev/null
  fail "could not commit the new version: $file is back to $old"
fi
echo "raised $old $new"
