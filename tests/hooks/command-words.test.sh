#!/bin/sh
# shellcheck disable=SC2016 # Dollars in quotes are the input.
#
# Tests what a simple command comes down to after the splitter and command-words.awk.
# Every rule reads this form, so what's settled here needn't go through the hook.

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
# shellcheck source=tests/lib/assert.sh
. "$ROOT/tests/lib/assert.sh"

lib="$ROOT/plugins/dev-workflow/scripts/lib"

# expect <input> <line>...: prints exactly these lines, with | ending each word.
expect() {
  _input=$1
  shift
  _expected=$(printf '%s\n' "$@")
  _split=$(printf '%s\n' "$_input" | awk -v 'WORD_END=\036' -f "$lib/split-command.awk") ||
    _assert_fail "the splitter failed on: $_input"
  _words=$(printf '%s\n' "$_split" | DW_ROOT=/the/project awk -f "$lib/command-words.awk") ||
    _assert_fail "command-words.awk failed on: $_input"
  _actual=$(printf '%s\n' "$_words" | tr '\036' '|')
  [ "$_actual" = "$_expected" ] || _assert_fail "for input:
$_input
expected:
$_expected
got:
$_actual"
}

# --- Prefixes

for prefix in \
  'env A=1' \
  'env -i A=1' \
  'env -u A B=1' \
  'env -- A=1' \
  'sudo' \
  'sudo -n' \
  'sudo -u bob' \
  'sudo --user=bob A=1' \
  'sudo --user bob' \
  'command' \
  'command -p' \
  'exec' \
  'exec -a name' \
  'exec -c' \
  'nohup' \
  'timeout 600' \
  'timeout -k 5 600' \
  'timeout --signal KILL --preserve-status 600' \
  'nice' \
  'nice -5' \
  'nice -n 5' \
  'nice --adjustment=5' \
  '/usr/bin/env' \
  '/usr/bin/env A=1' \
  '/usr/bin/timeout 5' \
  '/usr/bin/nice' \
  'sudo env A=1 command' \
  'nice timeout 5 env A=1' \
  '2>/dev/null' \
  '2> /dev/null' \
  '2>/dev/null A=1' \
  '>out' \
  '>>out' \
  '&>out' \
  '< in' \
  'A=1' \
  'A=1 env B=2'; do
  expect "$prefix gh pr merge 1" 'gh|pr|merge|1|'
  expect "$prefix npm run check" 'npm|run|check|'
done

# Nothing left to run.
expect 'exec 2>&1'
expect 'env'
expect 'sudo -v'
expect 'timeout 5'
expect '>out'

# Asking about a command doesn't run it.
expect 'command -v gh pr merge 1' 'command|-v|gh|pr|merge|1|'
expect 'command -V git' 'command|-V|git|'
expect 'command -pv git' 'command|-pv|git|'

# --- A shell running a script

expect 'sh scripts/verify' 'scripts/verify|'
expect 'bash scripts/verify --fast' 'scripts/verify|--fast|'
expect 'sh ./scripts/verify' 'scripts/verify|'
expect '/bin/sh scripts/verify' 'scripts/verify|'
expect 'bash -e scripts/verify' 'scripts/verify|'
expect 'bash -o pipefail scripts/verify' 'scripts/verify|'
expect 'sh +x scripts/verify' 'scripts/verify|'
expect 'bash --norc scripts/verify' 'scripts/verify|'
expect 'sh -- scripts/verify' 'scripts/verify|'
expect 'nice sh scripts/verify' 'scripts/verify|'
expect 'sh /the/project/scripts/verify' 'scripts/verify|'
# Only a script: the rest can't be read, and a script in a folder isn't the tool.
expect 'sh -c "npm test"' 'sh|-c|npm test|'
expect 'bash -ec "npm test"' 'bash|-ec|npm test|'
expect 'sh -s' 'sh|-s|'
expect 'sh' 'sh|'
expect 'sh scripts/gh pr merge 1' 'scripts/gh|pr|merge|1|'
expect 'sh env A=1' 'env|A=1|'

# --- Quotes, paths and the tools' own options

expect '"gh" "pr" merge 1' 'gh|pr|merge|1|'
expect "'git' commit" 'git|commit|'
expect 'g\h pr' 'gh|pr|'
expect '/opt/homebrew/bin/gh pr' 'gh|pr|'
expect '/usr/bin/git status' 'git|status|'
expect './scripts/check x' 'scripts/check|x|'
expect '/the/project/scripts/check' 'scripts/check|'
expect '/the/project-other/check' '/the/project-other/check|'
expect '/usr/local/bin/dropdb app' 'dropdb|app|'
expect '/usr/bin/docker compose' 'docker|compose|'

expect 'gh -R o/r pr merge 1' 'gh|pr|merge|1|'
expect 'gh --repo o/r pr merge 1' 'gh|pr|merge|1|'
expect 'gh --repo=o/r pr merge 1' 'gh|pr|merge|1|'
expect 'gh -Ro/r pr merge 1' 'gh|pr|merge|1|'
expect 'gh pr -R o/r merge 1' 'gh|pr|merge|1|'
expect 'gh pr merge -R o/r 1' 'gh|pr|merge|-R|o/r|1|'
# gh api has no action word, so what follows it is left as it is.
expect 'gh api -X POST path -f a=b' 'gh|api|-X|POST|path|-f|a=b|'
expect 'gh api -f a=b path' 'gh|api|-f|a=b|path|'
expect 'gh api path' 'gh|api|path|'
expect 'gh -R o/r api --method PUT path' 'gh|api|--method|PUT|path|'

expect 'git -c k=v commit' 'git|commit|'
expect 'git --no-pager log' 'git|log|'
expect 'git --git-dir .git --work-tree=. push' 'git|push|'
# -C decides which repo a rule judges, so it stays, and in order.
expect 'git -C path merge x' 'git|-C|path|merge|x|'
expect 'git -c a=b -C "a path" -c c=d -C sub commit' 'git|-C|a path|-C|sub|commit|'
expect 'git -C' 'git|'

# --- Redirections, attached or not

expect 'a 2>&1' 'a|'
expect 'a 2> out b' 'a|b|'
expect 'a >out b' 'a|b|'
expect 'a > out b' 'a|b|'
expect 'a >> out b' 'a|b|'
expect 'a &> out b' 'a|b|'
expect 'a < in b' 'a|b|'
expect 'a >&2 b' 'a|b|'
expect 'a>out' 'a|'
expect 'a>out b' 'a|b|'
expect 'a> out b' 'a|b|'
expect 'a>>out b' 'a|b|'
expect 'a&>out b' 'a|b|'
expect 'a<in b' 'a|b|'
expect 'a>&2 b' 'a|b|'
expect 'a>out 2>&1 b' 'a|b|'
expect 'a>out>err b' 'a|b|'
expect 'a>out 2>err' 'a|'
expect 'a2>out b' 'a2|b|'
expect 'git commit --no-verify>out' 'git|commit|--no-verify|'
expect 'npm run check>out' 'npm|run|check|'
expect 'gh pr merge 1 --body "">/dev/null' 'gh|pr|merge|1|--body||'
expect "gh pr merge 1 --body ''>/dev/null --squash" 'gh|pr|merge|1|--body||--squash|'
expect 'a --flag="x y">out b' 'a|--flag=x y|b|'

# What only looks like one.
expect 'a "x>y" b' 'a|x>y|b|'
expect "a 'x>y' b" 'a|x>y|b|'
expect 'a x\>y b' 'a|x>y|b|'
expect 'a "2>out" b' 'a|2>out|b|'
expect 'a --file=<(b) c' 'b|' 'a|--file=<(b)|c|'
expect 'a <(b) c' 'b|' 'a|<(b)|c|'
unit=$(printf '\037')
expect 'a "$(cat <<EOF
says "x > y" and it'"'"'s fine
EOF
)" b' 'cat|<<EOF|' "a|\$(cat <<EOF${unit}says x > y and it's fine${unit}EOF${unit})|b|"

# Heredocs and here-strings stay, as a sign that stdin holds text.
expect 'a <<EOF
text
EOF' 'a|<<EOF|'
expect "a - <<'EOF'
text
EOF" 'a|-|<<EOF|'
expect "a -<<'EOF'
text
EOF" 'a|-|<<EOF|'
expect 'a <<< text' 'a|<<<|text|'
expect 'a<<<text' 'a|<<<text|'

# --- Decoding

expect "a \$'x\\ty'" "a|x$(printf '\t')y|"
expect "a \$'x\\ny'" "a|x${unit}y|"
expect 'a "b\"c" "d\e"' 'a|b"c|d\e|'
expect 'a $X "$Y" `b`' 'b|' 'a|$X|$Y|`b`|'
