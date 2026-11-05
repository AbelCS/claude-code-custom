#!/bin/sh
# install-hooks.sh plan|apply <root> <templates>: copies the git hooks into .githooks/,
# keeps the ones the project edited, and turns them on the way the repo allows.

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
# shellcheck source=tests/lib/assert.sh
. "$ROOT/tests/lib/assert.sh"

INSTALL="$ROOT/plugins/dev-workflow/scripts/setup/install-hooks.sh"
LEDGER="$ROOT/plugins/dev-workflow/scripts/setup/ledger.sh"
TEMPLATES="$ROOT/plugins/dev-workflow/skills/setup/templates/githooks"
HOOKS="commit-msg pre-commit pre-push"
work=$(tmp_dir)

# A hooks path in this machine's git config must not leak in. Tests set one here.
GIT_CONFIG_GLOBAL=$work/gitconfig
GIT_CONFIG_NOSYSTEM=1
: >"$GIT_CONFIG_GLOBAL"
export GIT_CONFIG_GLOBAL GIT_CONFIG_NOSYSTEM

run() { # <plan|apply> <root> [templates] [flags...]: the JSON lines, failing unless exit 0
  _mode=$1
  _root=$2
  _tpl=${3:-$TEMPLATES}
  [ "$#" -lt 3 ] || shift
  shift 2
  _out=$(sh "$INSTALL" "$_mode" "$_root" "$_tpl" "$@" 2>&1) ||
    _assert_fail "install-hooks.sh $_mode failed on $_root:
$_out"
  printf '%s\n' "$_out" | jq -e -s 'length > 0 and all(.[]; (.path | type) == "string" and
    (.action | IN("create", "update", "keep", "conflict")))' >/dev/null ||
    _assert_fail "not one JSON line per path:
$_out"
  printf '%s\n' "$_out"
}

action() { # <json lines> <path>
  printf '%s\n' "$1" | jq -r --arg p "$2" 'select(.path == $p) | .action'
}

detail() { # <json lines> <path>
  printf '%s\n' "$1" | jq -r --arg p "$2" 'select(.path == $p) | .detail // ""'
}

hooks_path() { git -C "$1" config --local --get core.hooksPath; }

installed() { # <root>: every file is the template's, and each hook is executable
  for f in $HOOKS dw-lib.sh; do
    assert_file_same "$1/.githooks/$f" "$TEMPLATES/$f"
  done
  for f in $HOOKS; do
    assert_exit 0 test -x "$1/.githooks/$f"
  done
}

# --- no package.json: core.hooksPath, and plan writes nothing

r=$work/plain
new_repo "$r"
out=$(run plan "$r")
assert_exit 0 test "$(action "$out" .githooks/pre-commit)" = create
assert_exit 0 test "$(action "$out" core.hooksPath)" = update
assert_exit 1 test -e "$r/.githooks"
assert_exit 1 hooks_path "$r"
out=$(run apply "$r")
installed "$r"
assert_exit 0 test "$(hooks_path "$r")" = .githooks
assert_exit 0 test "$(sh "$LEDGER" get "$r/.claude/dev-workflow.json" .githooks/pre-push)" = \
  "$(sh "$LEDGER" hash "$TEMPLATES/pre-push")"

# A rerun keeps everything.
out=$(run apply "$r")
assert_exit 0 test "$(printf '%s\n' "$out" | jq -r .action | sort -u)" = keep

# A hook that lost its mode is made executable again.
chmod 644 "$r/.githooks/pre-push"
out=$(run apply "$r")
assert_exit 0 test "$(action "$out" .githooks/pre-push)" = update
assert_exit 0 test -x "$r/.githooks/pre-push"

# A path with spaces works too.
r="$work/a b/repo"
new_repo "$r"
printf '{ "scripts": {} }\n' >"$r/package.json"
run apply "$r" >/dev/null
installed "$r"
assert_exit 0 test "$(hooks_path "$r")" = .githooks

# --- templates from a plugin copy that lost its modes still install executable

r=$work/modes
new_repo "$r"
plain=$(tmp_dir)
cp "$TEMPLATES"/* "$plain/"
chmod 644 "$plain"/*
run apply "$r" "$plain" >/dev/null
installed "$r"

# --- an edited hook is left alone and reported; an untouched one is updated

r=$work/edited
new_repo "$r"
run apply "$r" >/dev/null
printf '# my change\n' >>"$r/.githooks/pre-commit"
cp "$r/.githooks/pre-commit" "$work/edited-hook"
newer=$(tmp_dir)
cp -p "$TEMPLATES"/* "$newer/"
printf '# newer\n' >>"$newer/pre-commit"
printf '# newer\n' >>"$newer/commit-msg"
out=$(run apply "$r" "$newer")
assert_exit 0 test "$(action "$out" .githooks/pre-commit)" = conflict
assert_contains "$(detail "$out" .githooks/pre-commit)" "# my change"
assert_file_same "$r/.githooks/pre-commit" "$work/edited-hook"
assert_exit 0 test "$(action "$out" .githooks/commit-msg)" = update
assert_file_same "$r/.githooks/commit-msg" "$newer/commit-msg"
assert_exit 0 test "$(action "$out" .githooks/pre-push)" = keep

# --- package.json: a prepare script, keeping the other scripts and the layout

r=$work/node
new_repo "$r"
printf '{\n\t"name": "x",\n\t"scripts": {\n\t\t"test": "node --test"\n\t}\n}\n' >"$r/package.json"
out=$(run apply "$r")
assert_exit 0 test "$(action "$out" package.json)" = update
assert_exit 0 test "$(jq -r .scripts.test "$r/package.json")" = "node --test"
assert_exit 0 test "$(jq -r .scripts.prepare "$r/package.json")" = "git config core.hooksPath .githooks || exit 0"
assert_exit 0 grep -q "$(printf '^\t\t"prepare"')" "$r/package.json"
assert_exit 0 test "$(hooks_path "$r")" = .githooks
installed "$r"
cp "$r/package.json" "$work/node-first"
out=$(run apply "$r")
assert_exit 0 test "$(action "$out" package.json)" = keep
assert_file_same "$r/package.json" "$work/node-first"

# An existing prepare keeps running first.
r=$work/node-prepare
new_repo "$r"
printf '{\n  "scripts": {\n    "prepare": "npm run build"\n  }\n}\n' >"$r/package.json"
run apply "$r" >/dev/null
assert_exit 0 test "$(jq -r .scripts.prepare "$r/package.json")" = \
  "npm run build && (git config core.hooksPath .githooks || exit 0)"
assert_exit 0 grep -q '^    "prepare"' "$r/package.json"
# No scripts at all.
r=$work/node-bare
new_repo "$r"
printf '{"name": "x"}\n' >"$r/package.json"
run apply "$r" >/dev/null
assert_exit 0 test "$(jq -c .scripts "$r/package.json")" = '{"prepare":"git config core.hooksPath .githooks || exit 0"}'

# --- husky: a block at the start of .husky/<hook>, between markers, keeping what's there

block_of() { # <file>: the dev-workflow block in it, markers and all
  sed -n '/^# dev-workflow:begin$/,/^# dev-workflow:end$/p' "$1"
}

r=$work/husky
new_repo "$r"
mkdir -p "$r/.husky"
printf 'npx lint-staged\n' >"$r/.husky/pre-commit"
# shellcheck disable=SC2016 # The text is a file's, not for this shell.
printf '#!/usr/bin/env sh\n. "$(dirname -- "$0")/_/husky.sh"\n\nnpm test\n' >"$r/.husky/commit-msg"
git -C "$r" config core.hooksPath .husky/_
out=$(run apply "$r")
assert_exit 0 test "$(action "$out" .husky/pre-commit)" = update
assert_exit 0 test "$(action "$out" .husky/pre-push)" = create
assert_exit 0 test "$(head -n 1 "$r/.husky/pre-commit")" = '# dev-workflow:begin'
assert_exit 0 test "$(tail -n 1 "$r/.husky/pre-commit")" = 'npx lint-staged'
assert_contains "$(block_of "$r/.husky/pre-commit")" '.githooks/pre-commit "$@" || exit $?'
# After the shebang and husky's own line, which have to come first.
assert_exit 0 test "$(sed -n 3p "$r/.husky/commit-msg")" = '# dev-workflow:begin'
# shellcheck disable=SC2016 # The text is a file's, not for this shell.
assert_exit 0 test "$(sed -n 1,2p "$r/.husky/commit-msg")" = "$(printf '#!/usr/bin/env sh\n. "$(dirname -- "$0")/_/husky.sh"')"
assert_exit 0 test "$(tail -n 2 "$r/.husky/commit-msg")" = "$(printf '\nnpm test')"
assert_contains "$(block_of "$r/.husky/commit-msg")" '.githooks/commit-msg "$@" || exit $?'
assert_exit 0 test "$(head -n 1 "$r/.husky/pre-push")" = '# dev-workflow:begin'
assert_exit 0 test -x "$r/.husky/pre-push"
assert_exit 0 test "$(hooks_path "$r")" = .husky/_
installed "$r"
for h in $HOOKS; do cp "$r/.husky/$h" "$work/husky-first.$h"; done
out=$(run apply "$r")
for h in $HOOKS; do
  assert_exit 0 test "$(action "$out" ".husky/$h")" = keep
  assert_file_same "$r/.husky/$h" "$work/husky-first.$h"
done
# A hook file with no final newline keeps its text whole.
printf 'npx x' >"$r/.husky/pre-commit"
run apply "$r" >/dev/null
assert_exit 0 test "$(tail -n 1 "$r/.husky/pre-commit")" = 'npx x'
assert_exit 0 test "$(head -n 1 "$r/.husky/pre-commit")" = '# dev-workflow:begin'
# A block the project edited is left alone, and reported.
sed 's/|| exit \$?/# ours now/' "$r/.husky/commit-msg" >"$work/husky-edited"
cat "$work/husky-edited" >"$r/.husky/commit-msg"
out=$(run apply "$r")
assert_exit 0 test "$(action "$out" .husky/commit-msg)" = conflict
assert_contains "$(detail "$out" .husky/commit-msg)" '# ours now'
assert_file_same "$r/.husky/commit-msg" "$work/husky-edited"
# One that's what setup recorded, as an older plugin wrote it, is brought up to date.
block_of "$r/.husky/commit-msg" >"$work/husky-old-block"
sh "$LEDGER" set "$r/.claude/dev-workflow.json" .husky/commit-msg#dev-workflow "$(sh "$LEDGER" hash "$work/husky-old-block")"
out=$(run apply "$r")
assert_exit 0 test "$(action "$out" .husky/commit-msg)" = update
assert_file_same "$r/.husky/commit-msg" "$work/husky-first.commit-msg"
# A begin marker with no end is reported, and left alone.
printf '# dev-workflow:begin\nnpx y\n' >"$r/.husky/pre-commit"
cp "$r/.husky/pre-commit" "$work/husky-broken"
out=$(run apply "$r")
assert_exit 0 test "$(action "$out" .husky/pre-commit)" = conflict
assert_file_same "$r/.husky/pre-commit" "$work/husky-broken"

# A husky pre-push that reads git's input itself still leaves it for the dev-workflow
# hook, which blocks a push to main and runs the check on any other.
r=$work/husky-push
new_repo "$r"
git -C "$r" commit -q --allow-empty -m "chore: start"
git init -q --bare -b main "$work/husky-push.git"
git -C "$r" remote add origin "$work/husky-push.git"
git -C "$r" push -q origin main 2>/dev/null || _assert_fail "cannot seed the remote"
mkdir -p "$r/.husky/_"
# As husky 9 runs a hook: its own script in .husky/_ starts the project's with sh -e.
# shellcheck disable=SC2016 # The text is a file's, not for this shell.
printf '#!/bin/sh\nexec sh -e "$(dirname "$0")/../pre-push" "$@"\n' >"$r/.husky/_/pre-push"
chmod +x "$r/.husky/_/pre-push"
git -C "$r" config core.hooksPath .husky/_
# shellcheck disable=SC2016 # The text is a file's, not for this shell.
printf 'while read -r local_ref rest; do echo "husky saw $local_ref" >>"$HUSKY_LOG"; done\n' >"$r/.husky/pre-push"
run apply "$r" >/dev/null
printf "DW_DEFAULT_BRANCH='main'\nDW_CHECK='echo check ran >>\"\$HUSKY_LOG\"'\nDW_CI_ALLOWLIST=''\nDW_FORMATTERS=''\n" >"$r/.githooks/dev-workflow.env"
printf '.githooks\n.husky\n.claude\n' >>"$r/.git/info/exclude"
HUSKY_LOG=$work/husky.log
export HUSKY_LOG
git -C "$r" commit -q --allow-empty -m "chore: more"
: >"$HUSKY_LOG"
pushed=$(git -C "$r" push -q origin main 2>&1) && _assert_fail "a push to main got through husky:
$pushed"
assert_contains "$pushed" "don't push directly to main"
git -C "$r" switch -q -c feat/1-x
: >"$HUSKY_LOG"
pushed=$(git -C "$r" push -q origin feat/1-x 2>&1) || _assert_fail "a push of a branch failed:
$pushed"
assert_exit 0 test "$(cat "$HUSKY_LOG")" = "$(printf 'check ran\nhusky saw refs/heads/feat/1-x')"

# --- lefthook: reported with the lines to add, and its config left alone

r=$work/lefthook
new_repo "$r"
printf 'pre-commit:\n  commands:\n    lint:\n      run: npx eslint\n' >"$r/lefthook.yml"
cp "$r/lefthook.yml" "$work/lefthook-first"
out=$(run apply "$r")
assert_exit 0 test "$(action "$out" lefthook.yml)" = conflict
assert_contains "$(detail "$out" lefthook.yml)" "run: .githooks/pre-commit"
assert_contains "$(detail "$out" lefthook.yml)" "run: .githooks/commit-msg {1}"
assert_contains "$(detail "$out" lefthook.yml)" "use_stdin: true"
assert_file_same "$r/lefthook.yml" "$work/lefthook-first"
assert_exit 1 hooks_path "$r"
installed "$r"
# Once the lines are in, it's kept.
# Only the lines are looked for, not where they sit.
detail "$out" lefthook.yml | sed -n '/^pre-commit:$/,$p' >>"$r/lefthook.yml"
out=$(run apply "$r")
assert_exit 0 test "$(action "$out" lefthook.yml)" = keep

# --- another core.hooksPath is never overwritten

r=$work/other-path
new_repo "$r"
git -C "$r" config core.hooksPath tools/hooks
out=$(run apply "$r")
assert_exit 0 test "$(action "$out" core.hooksPath)" = conflict
assert_contains "$(detail "$out" core.hooksPath)" 'tools/hooks/pre-commit'
assert_contains "$(detail "$out" core.hooksPath)" '.githooks/pre-commit "$@"'
assert_exit 0 test "$(hooks_path "$r")" = tools/hooks
installed "$r"

# --- a hooks path from git's global config is in effect here too, and never overridden

r=$work/global-path
new_repo "$r"
printf '{\n  "name": "x"\n}\n' >"$r/package.json"
cp "$r/package.json" "$work/global-package"
git config --file "$GIT_CONFIG_GLOBAL" core.hooksPath "$work/global hooks"
out=$(run apply "$r")
assert_exit 0 test "$(action "$out" core.hooksPath)" = conflict
assert_contains "$(detail "$out" core.hooksPath)" "$work/global hooks, from git's global config"
assert_contains "$(detail "$out" core.hooksPath)" "$work/global hooks/pre-push: [ ! -x .githooks/pre-push ] || .githooks/pre-push \"\$@\" || exit"
assert_contains "$(detail "$out" core.hooksPath)" 'git config core.hooksPath .githooks'
assert_exit 1 hooks_path "$r"
# No prepare script either, as npm install would set it over the global one.
assert_exit 0 test -z "$(action "$out" package.json)"
assert_file_same "$r/package.json" "$work/global-package"
installed "$r"
# A global .githooks is this plugin's own.
git config --file "$GIT_CONFIG_GLOBAL" core.hooksPath .githooks
out=$(run apply "$r")
assert_exit 0 test "$(action "$out" core.hooksPath)" = keep
assert_exit 1 hooks_path "$r"
: >"$GIT_CONFIG_GLOBAL"

# --- hooks in .git/hooks: never stopped without a word

hook_log=$work/old-hooks.log
export hook_log
old_hooks() { # <repo>: an executable pre-commit and post-merge in .git/hooks, and a sample
  # shellcheck disable=SC2016 # The text is a file's, not for this shell.
  printf '#!/bin/sh\necho "old pre-commit $*" >>"$hook_log"\n' >"$1/.git/hooks/pre-commit"
  # shellcheck disable=SC2016 # The text is a file's, not for this shell.
  printf '#!/bin/sh\necho old post-merge >>"$hook_log"\n' >"$1/.git/hooks/post-merge"
  printf '#!/bin/sh\n' >"$1/.git/hooks/pre-push.sample"
  chmod +x "$1/.git/hooks/pre-commit" "$1/.git/hooks/post-merge" "$1/.git/hooks/pre-push.sample"
}

# Without the person's yes, a conflict naming them, and core.hooksPath stays unset.
r=$work/git-hooks
new_repo "$r"
old_hooks "$r"
printf '{\n  "name": "x"\n}\n' >"$r/package.json"
cp "$r/package.json" "$work/git-hooks-package"
out=$(run apply "$r")
assert_exit 0 test "$(action "$out" .git/hooks)" = conflict
assert_contains "$(detail "$out" .git/hooks)" 'post-merge, pre-commit'
assert_not_contains "$(detail "$out" .git/hooks)" 'sample'
assert_contains "$(detail "$out" .git/hooks)" '.githooks/pre-commit.local'
assert_exit 0 test -z "$(action "$out" core.hooksPath)"
assert_exit 0 test -z "$(action "$out" package.json)"
assert_exit 1 hooks_path "$r"
assert_file_same "$r/package.json" "$work/git-hooks-package"
assert_exit 0 test -x "$r/.git/hooks/pre-commit"
installed "$r"

# With it, planned without writing anything, then each moves into .githooks: one with a
# dev-workflow hook of its name as <name>.local, which that hook runs first.
out=$(run plan "$r" "$TEMPLATES" --move-git-hooks)
assert_exit 0 test "$(action "$out" .git/hooks/pre-commit)" = update
assert_contains "$(detail "$out" .git/hooks/pre-commit)" '.githooks/pre-commit.local'
assert_exit 0 test "$(action "$out" .git/hooks/post-merge)" = update
assert_exit 0 test "$(action "$out" core.hooksPath)" = update
assert_exit 0 test -x "$r/.git/hooks/pre-commit"
assert_exit 1 test -e "$r/.githooks/pre-commit.local"
assert_exit 1 hooks_path "$r"
out=$(run apply "$r" "$TEMPLATES" --move-git-hooks)
assert_exit 0 test "$(action "$out" package.json)" = update
assert_exit 0 test "$(hooks_path "$r")" = .githooks
assert_exit 1 test -e "$r/.git/hooks/pre-commit"
assert_exit 1 test -e "$r/.git/hooks/post-merge"
assert_exit 0 test -x "$r/.githooks/pre-commit.local"
assert_exit 0 test -x "$r/.githooks/post-merge"
assert_exit 0 test -e "$r/.git/hooks/pre-push.sample"
installed "$r"
: >"$hook_log"
git -C "$r" commit -q --allow-empty -m "chore: start" 2>/dev/null || _assert_fail "a commit failed after the move"
assert_exit 0 test "$(cat "$hook_log")" = 'old pre-commit '
# A rerun has nothing to move, and keeps everything.
out=$(run apply "$r" "$TEMPLATES" --move-git-hooks)
assert_exit 0 test "$(printf '%s\n' "$out" | jq -r .action | sort -u)" = keep

# One that can't move, as its place in .githooks is taken, moves none, and leaves
# core.hooksPath unset.
r=$work/git-hooks-taken
new_repo "$r"
old_hooks "$r"
mkdir -p "$r/.githooks"
printf '#!/bin/sh\n' >"$r/.githooks/post-merge"
out=$(run apply "$r" "$TEMPLATES" --move-git-hooks)
assert_exit 0 test "$(action "$out" .git/hooks)" = conflict
assert_contains "$(detail "$out" .git/hooks)" '.githooks/post-merge is already there'
assert_exit 0 test -x "$r/.git/hooks/pre-commit"
assert_exit 1 test -e "$r/.githooks/pre-commit.local"
assert_exit 1 hooks_path "$r"

# --- usage

assert_exit 2 sh "$INSTALL"
assert_exit 2 sh "$INSTALL" apply "$work/plain"
assert_exit 2 sh "$INSTALL" apply "$work/missing" "$TEMPLATES"
assert_exit 2 sh "$INSTALL" apply "$work/plain" "$work/missing"
assert_exit 2 sh "$INSTALL" apply "$work/plain" "$TEMPLATES" --other

# --- a folder setup writes in that leads out of the repo is refused

for d in .githooks .claude .husky; do
  r=$work/escape-$d
  new_repo "$r"
  mkdir -p "$work/away-$d"
  ln -s "$work/away-$d" "$r/$d"
  for m in plan apply; do
    assert_exit 2 sh "$INSTALL" "$m" "$r" "$TEMPLATES"
    assert_contains "$(sh "$INSTALL" "$m" "$r" "$TEMPLATES" 2>&1)" 'outside the project'
  done
  assert_exit 0 test -z "$(ls -A "$work/away-$d")"
  assert_exit 1 hooks_path "$r"
done
