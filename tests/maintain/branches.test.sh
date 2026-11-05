#!/bin/sh
# merged-branches.sh <root>: one "<branch> delete|keep <reason>" line per local branch.
# Only a branch whose tip is the tip of a merged pull request of the same name is
# deleted. The current and default branches are always kept, and a branch checked out
# in another worktree names it. gh is a stub: no test reads a real repo's pull requests.

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
# shellcheck source=tests/lib/assert.sh
. "$ROOT/tests/lib/assert.sh"

MB="$ROOT/plugins/dev-workflow/scripts/maintain/merged-branches.sh"
work=$(tmp_dir)

# The stub prints $work/prs.json for the merged pull requests, logs its arguments, and
# fails on GH_FAIL.
cat >"$work/gh" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >>"$work/calls"
[ -z "\${GH_FAIL:-}" ] || { echo "HTTP 401: Bad credentials" >&2; exit 1; }
case "\$*" in
  "pr list "*) cat "$work/prs.json" ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$work/gh"
DW_GH="$work/gh"
export DW_GH

commit() { # <repo> <message>
  git -C "$1" commit -q --allow-empty -m "$2" || _assert_fail "could not commit in $1"
}
tip() { # <repo> <ref>
  git -C "$1" rev-parse "$2"
}

# --- the repo: a remote, and one branch per case

origin=$work/origin.git
git init -q --bare -b main "$origin"
r=$work/repo
new_repo "$r"
commit "$r" "chore: start"
git -C "$r" remote add origin "$origin"
git -C "$r" push -q -u origin main 2>/dev/null

branch() { # <name>: a new branch off main with one commit, left checked out on main
  git -C "$r" switch -q -c "$1" main
  commit "$r" "feat: $1"
  git -C "$r" switch -q main
}

branch feat/1-merged     # its merged pull request has this tip
branch feat/2-gone       # pushed, then its remote branch deleted, with no pull request
branch feat/3-ahead      # a commit added after its pull request merged
branch feat/4-moved      # its pull request merged at a tip this branch doesn't have
branch feat/5-open       # no pull request merged
branch feat/6-current    # merged, but checked out here
branch feat/7-worktree   # merged, and checked out in another worktree
branch feat/8-kept-wt    # not merged, and checked out in another worktree

git -C "$r" push -q -u origin feat/2-gone 2>/dev/null
git -C "$r" push -q origin --delete feat/2-gone 2>/dev/null
git -C "$r" fetch -q --prune

merged_3=$(tip "$r" feat/3-ahead)
git -C "$r" switch -q feat/3-ahead
commit "$r" "fix: after the merge"
git -C "$r" switch -q main

other=$(git -C "$r" commit-tree -m "elsewhere" "$(tip "$r" 'main^{tree}')")

wt=$work/wt
git -C "$r" worktree add -q "$wt" feat/7-worktree
wt8=$work/wt-8
git -C "$r" worktree add -q "$wt8" feat/8-kept-wt
git -C "$r" switch -q feat/6-current
# As git names them, with symlinks such as macOS's /var resolved.
wt_path=$(git -C "$wt" rev-parse --show-toplevel)
wt8_path=$(git -C "$wt8" rev-parse --show-toplevel)

# The merged pull requests, including a pull request merged from main itself, which
# never makes main a branch to delete.
jq -n \
  --arg m1 "$(tip "$r" feat/1-merged)" --arg m3 "$merged_3" --arg m4 "$other" \
  --arg m6 "$(tip "$r" feat/6-current)" --arg m7 "$(tip "$r" feat/7-worktree)" \
  --arg main "$(tip "$r" main)" '[
    {headRefName: "feat/1-merged", headRefOid: $m1},
    {headRefName: "feat/3-ahead", headRefOid: $m3},
    {headRefName: "feat/4-moved", headRefOid: $m4},
    {headRefName: "feat/6-current", headRefOid: $m6},
    {headRefName: "feat/7-worktree", headRefOid: $m7},
    {headRefName: "main", headRefOid: $main}
  ]' >"$work/prs.json"

run() { # <root>: the output, exit 0
  : >"$work/calls"
  _out=$(sh "$MB" "$1" 2>&1) || _assert_fail "merged-branches.sh $1 failed:
$_out"
  printf '%s\n' "$_out"
}

line_for() { # <output> <branch>: the line for the branch, which must be there once
  _lines=$(printf '%s\n' "$1" | awk -v b="$2" '$1 == b')
  [ "$(printf '%s\n' "$_lines" | grep -c .)" -eq 1 ] || _assert_fail "expected one line for $2 in:
$1"
  printf '%s\n' "$_lines"
}

action_is() { # <output> <branch> <delete|keep>
  _line=$(line_for "$1" "$2")
  [ "$(printf '%s\n' "$_line" | awk '{ print $2 }')" = "$3" ] || _assert_fail "expected $2 to be $3:
$_line"
}

out=$(run "$r")

# gh was asked for merged pull requests, with a limit past its default 30.
calls=$(cat "$work/calls")
assert_contains "$calls" "pr list"
assert_contains "$calls" "--state merged"
assert_contains "$calls" "--json headRefName,headRefOid"
assert_contains "$calls" "--limit"

action_is "$out" feat/1-merged delete
action_is "$out" feat/2-gone keep
assert_contains "$(line_for "$out" feat/2-gone)" "gone"
action_is "$out" feat/3-ahead keep
assert_contains "$(line_for "$out" feat/3-ahead)" "after"
action_is "$out" feat/4-moved keep
action_is "$out" feat/5-open keep
action_is "$out" feat/6-current keep
assert_contains "$(line_for "$out" feat/6-current)" "current"
action_is "$out" main keep
assert_contains "$(line_for "$out" main)" "default"
action_is "$out" feat/7-worktree delete
assert_contains "$(line_for "$out" feat/7-worktree)" "worktree $wt_path"
action_is "$out" feat/8-kept-wt keep
assert_contains "$(line_for "$out" feat/8-kept-wt)" "worktree $wt8_path"
assert_not_contains "$(line_for "$out" feat/1-merged)" "worktree"

# Every line is "<branch> delete|keep <reason>", and only proven ones are deletes.
printf '%s\n' "$out" | awk '$2 != "delete" && $2 != "keep" || NF < 3 { bad = 1 } END { exit bad }' ||
  _assert_fail "a line isn't \"<branch> delete|keep <reason>\":
$out"
[ "$(printf '%s\n' "$out" | awk '$2 == "delete"' | wc -l | tr -d ' ')" -eq 2 ] ||
  _assert_fail "expected exactly two deletes:
$out"

# It only reads: every branch and worktree is still there.
for b in feat/1-merged feat/7-worktree; do
  git -C "$r" rev-parse -q --verify "refs/heads/$b" >/dev/null || _assert_fail "$b was deleted"
done
[ -d "$wt" ] || _assert_fail "the worktree was removed"

# From a subfolder and from the worktree, the same branches.
mkdir -p "$r/sub"
assert_contains "$(run "$r/sub")" "feat/1-merged delete"
from_wt=$(run "$wt")
action_is "$from_wt" feat/7-worktree keep
assert_contains "$(line_for "$from_wt" feat/7-worktree)" "current"
action_is "$from_wt" feat/6-current delete

# --- the default branch from the project file

mkdir -p "$r/.claude"
printf '{ "schemaVersion": 1, "pluginVersion": "1.0.0", "defaultBranch": "feat/5-open", "commands": { "check": "true" } }\n' \
  >"$r/.claude/dev-workflow.json"
out=$(run "$r")
assert_contains "$(line_for "$out" feat/5-open)" "default"
rm -r "$r/.claude"

# --- gh failing, or giving what isn't a list: an error, and no line at all

: >"$work/calls"
assert_exit 2 env GH_FAIL=1 sh "$MB" "$r"
out=$(GH_FAIL=1 sh "$MB" "$r" 2>/dev/null)
[ -z "$out" ] || _assert_fail "printed lines although gh failed:
$out"

cp "$work/prs.json" "$work/prs.good"
printf '{"message": "nope"}\n' >"$work/prs.json"
assert_exit 2 sh "$MB" "$r"
cp "$work/prs.good" "$work/prs.json"

# --- usage

assert_exit 2 sh "$MB"
assert_exit 2 sh "$MB" "$work/no-such-folder"
plain=$(tmp_dir)
assert_exit 2 sh "$MB" "$plain"
