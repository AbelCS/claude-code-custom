#!/bin/sh
# Each hook runs <hook>.local next to it first, if it's there: a hook setup moved out of
# .git/hooks, which would otherwise stop running. Its failure stops the commit or push,
# and the dev-workflow hook still runs after it, on the same arguments and input.

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
# shellcheck source=tests/lib/assert.sh
. "$ROOT/tests/lib/assert.sh"

templates="$ROOT/plugins/dev-workflow/skills/setup/templates/githooks"

# The owner's own git settings must not change a result.
GIT_CONFIG_GLOBAL=/dev/null
GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL GIT_CONFIG_NOSYSTEM
unset LC_ALL

repo="$(tmp_dir)/a b/repo"
new_repo "$repo"
hooks="$repo/.githooks"
mkdir -p "$hooks" "$repo/scripts"
cp "$templates"/* "$hooks/"
git -C "$repo" config core.hooksPath .githooks
printf '.githooks\nscripts\n' >>"$repo/.git/info/exclude"
LOCAL_LOG=$(tmp_dir)/log
export LOCAL_LOG
cat >"$hooks/dev-workflow.env" <<'ENV'
DW_DEFAULT_BRANCH='main'
DW_CHECK='echo check ran >>"$LOCAL_LOG"'
DW_CI_ALLOWLIST=''
DW_FORMATTERS='*.txt|scripts/fmt'
ENV
# shellcheck disable=SC2016 # The text is a file's, not for this shell.
printf '#!/bin/sh\necho formatter ran >>"$LOCAL_LOG"\n' >"$repo/scripts/fmt"
chmod +x "$repo/scripts/fmt"

local_hook() { # <hook> <exit status>: a .local that logs what it got, then exits
  cat >"$hooks/$1.local" <<EOF
#!/bin/sh
printf '$1.local[%s] LC_ALL=%s\n' "\$*" "\${LC_ALL-unset}" >>"\$LOCAL_LOG"
[ "$1" != pre-push ] || sed 's/^/stdin: /' >>"\$LOCAL_LOG"
exit $2
EOF
  chmod +x "$hooks/$1.local"
}

log() { cat "$LOCAL_LOG"; }

# --- pre-commit

printf 'x\n' >"$repo/a.txt"
git -C "$repo" add a.txt
local_hook pre-commit 3
: >"$LOCAL_LOG"
assert_exit 1 git -C "$repo" commit -q -m 'chore: start'
assert_exit 0 test "$(log)" = 'pre-commit.local[] LC_ALL=unset'
local_hook pre-commit 0
: >"$LOCAL_LOG"
assert_exit 0 git -C "$repo" commit -q -m 'chore: start'
assert_exit 0 test "$(log)" = "$(printf 'pre-commit.local[] LC_ALL=unset\nformatter ran')"
rm "$hooks/pre-commit.local"

# --- commit-msg: the message file, and the caller's locale, not the hook's own

local_hook commit-msg 4
: >"$LOCAL_LOG"
assert_exit 1 git -C "$repo" commit -q --allow-empty -m 'chore: more'
assert_contains "$(log)" 'commit-msg.local[.git/COMMIT_EDITMSG] LC_ALL=unset'
local_hook commit-msg 0
# It passing doesn't pass a bad message: the dev-workflow hook still runs.
assert_exit 1 git -C "$repo" commit -q --allow-empty -m 'not conventional'
assert_exit 0 git -C "$repo" commit -q --allow-empty -m 'chore: more'
rm "$hooks/commit-msg.local"

# --- pre-push: git's input reaches both

git init -q --bare -b main "$repo.remote.git"
git -C "$repo" remote add origin "$repo.remote.git"
git -C "$repo" push -q --no-verify origin main 2>/dev/null || _assert_fail "cannot seed the remote"
git -C "$repo" commit -q --allow-empty -m 'chore: again'
local_hook pre-push 0
: >"$LOCAL_LOG"
out=$(git -C "$repo" push -q origin main 2>&1) && _assert_fail "a push to main got through: $out"
assert_contains "$out" "don't push directly to main"
assert_contains "$(log)" "pre-push.local[origin $repo.remote.git] LC_ALL=unset"
assert_contains "$(log)" 'stdin: refs/heads/main '
git -C "$repo" switch -q -c feat/1-x
: >"$LOCAL_LOG"
assert_exit 0 git -C "$repo" push -q origin feat/1-x
assert_contains "$(log)" 'stdin: refs/heads/feat/1-x '
assert_contains "$(log)" 'check ran'
# Its failure stops the push, before the check.
local_hook pre-push 5
git -C "$repo" commit -q --allow-empty -m 'chore: once more (#1)'
: >"$LOCAL_LOG"
assert_exit 1 git -C "$repo" push -q origin feat/1-x
assert_not_contains "$(log)" 'check ran'

# --- one that isn't executable is skipped, as git would, and said so

chmod -x "$hooks/pre-push.local"
: >"$LOCAL_LOG"
out=$(git -C "$repo" push -q origin feat/1-x 2>&1) || _assert_fail "the push failed: $out"
assert_contains "$out" "pre-push.local isn't executable, so it was skipped"
assert_exit 0 test "$(log)" = 'check ran'
