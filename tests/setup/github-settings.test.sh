#!/bin/sh
# github-settings.sh [--plan] <owner/repo>: squash merges only, with the pull
# request's title and a blank message, and merged branches deleted. gh is a stub:
# no test calls the real GitHub API.

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
# shellcheck source=tests/lib/assert.sh
. "$ROOT/tests/lib/assert.sh"

GS="$ROOT/plugins/dev-workflow/scripts/setup/github-settings.sh"
work=$(tmp_dir)

# The stub answers a GET with $work/repo.json, logs every call, and fails on
# GH_FAIL.
cat >"$work/gh" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >>"$work/calls"
[ -z "\${GH_FAIL:-}" ] || { echo "HTTP 404: Not Found" >&2; exit 1; }
case "\$*" in
  *PATCH*) exit 0 ;;
  "api repos/"*) cat "$work/repo.json" ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$work/gh"
export DW_GH="$work/gh"

repo_json() { # <admin> <squash> <merge> <rebase> <title> <message> <delete>
  jq -n --argjson a "$1" --argjson s "$2" --argjson m "$3" --argjson r "$4" --arg t "$5" --arg msg "$6" --argjson d "$7" \
    '{full_name: "o/r", permissions: {admin: $a}, allow_squash_merge: $s, allow_merge_commit: $m,
      allow_rebase_merge: $r, squash_merge_commit_title: $t, squash_merge_commit_message: $msg,
      delete_branch_on_merge: $d}' >"$work/repo.json"
}

line() { # <args...>: the one JSON line, exit 0
  : >"$work/calls"
  _out=$(sh "$GS" "$@" 2>&1) || _assert_fail "github-settings.sh $* failed:
$_out"
  printf '%s\n' "$_out" | jq -e -s 'length == 1 and .[0].path == "github:o/r"' >/dev/null ||
    _assert_fail "not one JSON line:
$_out"
  printf '%s\n' "$_out"
}

# --- GitHub's defaults: everything to change

repo_json true true true true COMMIT_OR_PR_TITLE COMMIT_MESSAGES false
out=$(line --plan o/r)
assert_exit 0 test "$(printf '%s' "$out" | jq -r .action)" = update
assert_contains "$out" 'allow_merge_commit'
assert_contains "$out" 'squash_merge_commit_message'
assert_not_contains "$(cat "$work/calls")" PATCH

out=$(line o/r)
assert_exit 0 test "$(printf '%s' "$out" | jq -r .action)" = update
patch=$(grep PATCH "$work/calls")
assert_contains "$patch" 'repos/o/r'
for f in allow_squash_merge=true allow_merge_commit=false allow_rebase_merge=false \
  squash_merge_commit_title=PR_TITLE squash_merge_commit_message=BLANK delete_branch_on_merge=true; do
  assert_contains "$patch" "$f"
done

# --- already right: kept, with no change sent

repo_json true true false false PR_TITLE BLANK true
out=$(line o/r)
assert_exit 0 test "$(printf '%s' "$out" | jq -r .action)" = keep
assert_not_contains "$(cat "$work/calls")" PATCH

# --- not an admin: a conflict, and nothing sent

repo_json false true true true COMMIT_OR_PR_TITLE COMMIT_MESSAGES false
out=$(line o/r)
assert_exit 0 test "$(printf '%s' "$out" | jq -r .action)" = conflict
assert_contains "$out" admin
assert_not_contains "$(cat "$work/calls")" PATCH

# --- errors

assert_exit 2 sh "$GS" 'o/r; rm -rf x'
assert_exit 2 sh "$GS" o
assert_exit 2 env GH_FAIL=1 sh "$GS" --plan o/r
echo "github-settings: ok"
