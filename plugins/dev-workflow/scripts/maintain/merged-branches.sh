#!/bin/sh
# Usage: merged-branches.sh <root>
#
# Maintenance's branch sweep, for the repo holding <root>: which local branches are
# proven merged, so they can go, and which stay for a person to decide. Prints one line
# per local branch:
#   <branch> delete|keep <reason>
# A branch checked out in another worktree has "; worktree <path>" at the end of its
# reason, as that worktree has to be removed before the branch can be.
#
# Only "delete" is a decision. It means a pull request from a branch of that name was
# merged into the default branch with exactly this tip, so nothing on the branch is
# lost. A squash merge looks unmerged to git, which is why this asks GitHub rather than
# git. Everything else is "keep": the current branch, the default branch, a branch whose
# pull request merged into another base, such as an integration branch that may never
# land, a branch with commits after its merged pull request, one whose remote branch is
# gone with no merged pull request, and one with no merged pull request at all.
#
# It only reads: it deletes nothing. The merged pull requests come from
#   gh pr list --state merged --json headRefName,headRefOid,baseRefName --limit 1000
# so a branch whose pull request is older than the last 1000 merged is kept, which is
# safe. The default branch is the project file's defaultBranch, then origin's HEAD,
# then main.
#
# Exits 2 on bad usage, outside a repo, or if gh can't list the pull requests, having
# printed nothing. $DW_GH names gh, for tests.

die() {
  printf 'merged-branches.sh: %s\n' "$*" >&2
  exit 2
}

[ "$#" -eq 1 ] || die "usage: merged-branches.sh <root>"
for tool in git jq; do
  command -v "$tool" >/dev/null 2>&1 || die "missing required tool: $tool"
done
GH=${DW_GH:-gh}
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE

[ -d "$1" ] || die "not a folder: $1"
top=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null) || die "not in a git repo: $1"

current=$(git -C "$top" symbolic-ref -q --short HEAD) || current=

default=
if [ -f "$top/.claude/dev-workflow.json" ]; then
  default=$(jq -r '.defaultBranch | strings' "$top/.claude/dev-workflow.json" 2>/dev/null) || default=
fi
if [ -z "$default" ]; then
  default=$(git -C "$top" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null) &&
    default=${default#origin/}
fi
[ -n "$default" ] || default=main

prs=$(cd "$top" && "$GH" pr list --state merged --json headRefName,headRefOid,baseRefName --limit 1000) ||
  die "gh couldn't list the merged pull requests. Is it signed in, and is origin on GitHub?"
# "<name> <oid> <base>" a line. A pull request with no base named can't be proven
# merged into the default branch, so it never deletes.
merged=$(printf '%s\n' "$prs" | jq -r '
  if type == "array" then .[] else error("not a list") end
  | select((.headRefName | type) == "string" and (.headRefOid | type) == "string")
  | "\(.headRefName) \(.headRefOid) \(.baseRefName | strings // "?")"' 2>/dev/null) ||
  die "gh's list of merged pull requests isn't a list"

# "<branch> <path>" a line, for each branch checked out in a worktree.
worktrees=$(git -C "$top" worktree list --porcelain | awk '
  /^worktree / { path = substr($0, 10) }
  /^branch refs\/heads\// { print substr($0, 19) " " path }
') || die "couldn't list the worktrees"

branches=$(git -C "$top" for-each-ref --format='%(refname) %(objectname) %(upstream:track)' refs/heads/) ||
  die "couldn't list the branches"

while read -r ref tip track; do
  [ -n "$ref" ] || continue
  name=${ref#refs/heads/}

  if [ "$name" = "$current" ]; then
    action=keep reason="the current branch"
  elif [ "$name" = "$default" ]; then
    action=keep reason="the default branch"
  else
    # "<oid>:<base>" for each of its merged pull requests.
    prs_of=$(printf '%s\n' "$merged" | awk -v b="$name" '$1 == b { print $2 ":" $3 }')
    action=keep
    if [ -z "$prs_of" ]; then
      if [ "$track" = "[gone]" ]; then
        reason="its remote branch is gone, but no pull request of it was merged"
      else
        reason="no pull request of it was merged"
      fi
    else
      reason="its merged pull request had another tip"
      elsewhere=
      for pr in $prs_of; do
        oid=${pr%%:*} base=${pr#*:}
        if [ "$oid" = "$tip" ]; then
          if [ "$base" = "$default" ]; then
            action=delete reason="its pull request was merged into $default at this tip"
            break
          fi
          elsewhere=$base
        elif git -C "$top" merge-base --is-ancestor "$oid" "$tip" 2>/dev/null; then
          reason="it has commits after its merged pull request"
        fi
      done
      if [ "$action" = keep ] && [ -n "$elsewhere" ]; then
        reason="its pull request was merged into $elsewhere, not $default"
      fi
    fi
  fi

  if [ "$name" != "$current" ]; then
    path=$(printf '%s\n' "$worktrees" | awk -v b="$name" '$1 == b { sub(/^[^ ]+ /, ""); print; exit }')
    [ -z "$path" ] || reason="$reason; worktree $path"
  fi
  printf '%s %s %s\n' "$name" "$action" "$reason"
done <<BRANCHES
$branches
BRANCHES
