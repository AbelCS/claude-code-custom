#!/bin/sh
# Usage: github-settings.sh [--plan] <owner/repo>
#
# Sets the repo's merge settings on GitHub: squash merges only, the pull request's
# title as the commit's subject, a blank message, and merged branches deleted. Run it
# only with the person's approval for that repo. Prints one JSON line:
#   { "path": "github:<owner/repo>", "action": "update|keep|conflict", "detail": str }
# It reads the settings first: already right is "keep", and nothing is sent. Not an
# admin of the repo is "conflict", as GitHub would refuse. --plan only reads.
#
# The fields are the REST API's "Update a repository" body parameters, confirmed
# against https://docs.github.com/en/rest/repos/repos#update-a-repository on
# 2026-11-05. squash_merge_commit_title is required alongside
# squash_merge_commit_message, so they're always sent together.
#
# Exits 2 on bad usage, or if gh can't read or change the repo. $DW_GH names gh, for
# tests.

die() {
  printf 'github-settings.sh: %s\n' "$*" >&2
  exit 2
}

command -v jq >/dev/null 2>&1 || die "missing required tool: jq"
GH=${DW_GH:-gh}
plan=false
if [ "${1:-}" = --plan ]; then
  plan=true
  shift
fi
[ "$#" -eq 1 ] || die "usage: github-settings.sh [--plan] <owner/repo>"
repo=$1
case $repo in
  */*/* | /* | */ | *[!A-Za-z0-9._/-]*) die "not an owner/repo: $repo" ;;
  ?*/?*) ;;
  *) die "not an owner/repo: $repo" ;;
esac

# The settings wanted, as jq reads them and as gh api sends them.
wanted='{"allow_squash_merge": true, "allow_merge_commit": false, "allow_rebase_merge": false,
  "squash_merge_commit_title": "PR_TITLE", "squash_merge_commit_message": "BLANK",
  "delete_branch_on_merge": true}'

report() { # <action> <detail>
  jq -cn --arg p "github:$repo" --arg a "$1" --arg d "$2" '{path: $p, action: $a, detail: $d}'
}

current=$("$GH" api "repos/$repo") || die "gh couldn't read $repo, as it says above"
printf '%s\n' "$current" | jq -e 'type == "object"' >/dev/null 2>&1 || die "gh gave something other than the repo for $repo"

changes=$(printf '%s\n' "$current" | jq -r --argjson w "$wanted" '
  . as $c | [$w | to_entries[] | select($c[.key] != .value) | "\(.key) to \(.value)"] | join(", ")') ||
  die "couldn't compare the settings of $repo"
if [ -z "$changes" ]; then
  report keep "squash merges only, with the pull request's title and a blank message, and merged branches deleted"
  exit 0
fi
if [ "$(printf '%s\n' "$current" | jq -r '.permissions.admin // false')" != true ]; then
  report conflict "only an admin of $repo can change its merge settings: ask one to set $changes"
  exit 0
fi
if [ "$plan" = false ]; then
  out=$("$GH" api -X PATCH "repos/$repo" --silent \
    -F allow_squash_merge=true -F allow_merge_commit=false -F allow_rebase_merge=false \
    -f squash_merge_commit_title=PR_TITLE -f squash_merge_commit_message=BLANK \
    -F delete_branch_on_merge=true 2>&1) || die "gh couldn't change the settings of $repo: $out"
fi
report update "sets $changes"
