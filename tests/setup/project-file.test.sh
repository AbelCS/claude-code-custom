#!/bin/sh
# project-file.sh write|validate|existing-ci: the project file, checked against its
# schema, and the git hooks' dev-workflow.env generated from it.

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
# shellcheck source=tests/lib/assert.sh
. "$ROOT/tests/lib/assert.sh"

PF="$ROOT/plugins/dev-workflow/scripts/setup/project-file.sh"
VERSION=$(jq -r .version "$ROOT/plugins/dev-workflow/.claude-plugin/plugin.json")
work=$(tmp_dir)
# No stack has a reset list unless a test gives one.
mkdir "$work/no-stacks"
DW_STACKS_DIR=$work/no-stacks
export DW_STACKS_DIR

run() { # <args...>: the output, failing unless exit 0
  _out=$(sh "$PF" "$@" 2>&1) || _assert_fail "project-file.sh $* failed:
$_out"
  printf '%s\n' "$_out"
}

invalid() { # <json> <needle>: validate fails with exit 1, naming the needle
  printf '%s\n' "$1" >"$work/invalid.json"
  assert_exit 1 sh "$PF" validate "$work/invalid.json"
  assert_contains "$(sh "$PF" validate "$work/invalid.json" 2>&1)" "$2"
}

# env_value <env file> <name>: the value after sourcing it in a clean shell
env_value() {
  # shellcheck disable=SC2016 # The dollars are the inner shell's.
  env -i sh -c '. "$1" && eval "printf %s \"\${$2}\""' sh "$1" "$2"
}

# --- validate

# This repo's own project file is valid.
assert_exit 0 sh "$PF" validate "$ROOT/.claude/dev-workflow.json"

base='{"schemaVersion": 1, "pluginVersion": "1.0.0", "commands": {"check": "make check"}}'
printf '%s\n' "$base" >"$work/base.json"
assert_exit 0 sh "$PF" validate "$work/base.json"

invalid '{"schemaVersion": 1, "pluginVersion": "1.0.0", "commands": {"verify": "make verify"}}' "commands.check"
invalid '{"schemaVersion": 1, "pluginVersion": "1.0.0", "commands": {"check": ""}}' "commands.check"
invalid '{"schemaVersion": 1, "pluginVersion": "1.0.0"}' "commands"
invalid '{"schemaVersion": 1, "pluginVersion": "1.0.0", "commands": {"check": "x"}, "stack": "nextjs"}' "stack"
invalid '{"schemaVersion": 1, "pluginVersion": "1.0.0", "commands": {"check": "x"}, "testComands": []}' "testComands"
invalid '[1]' "object"
invalid '{ broken' "JSON"
invalid '{"schemaVersion": 1, "pluginVersion": "1.0.0", "commands": {"check": "x",
  "formatCheckStaged": [{"glob": "*.{ts,tsx}", "command": "npx prettier --check"}]}}' "one rule per glob"
invalid '{"schemaVersion": 1, "pluginVersion": "1.0.0", "commands": {"check": "x",
  "formatCheckStaged": [{"glob": "*.ts", "command": "npx prettier --write"}]}}' "check, not rewrite"
invalid '{"schemaVersion": 1, "pluginVersion": "1.0.0", "commands": {"check": "x",
  "formatCheckStaged": [{"glob": "*.go", "command": "gofmt -w"}]}}' "check, not rewrite"
invalid '{"schemaVersion": 1, "pluginVersion": "1.0.0", "commands": {"check": "x",
  "formatCheckStaged": [{"glob": "*.js", "command": "npx eslint --fix"}]}}' "check, not rewrite"
invalid '{"schemaVersion": 1, "pluginVersion": "1.0.0", "commands": {"check": "x",
  "formatCheckStaged": [{"glob": "*.js|x", "command": "y"}]}}' "glob"
assert_exit 2 sh "$PF" validate "$work/missing.json"

# --- write: a mixed repo with two formatters round-trips into the env file

r=$work/mixed
new_repo "$r"
cat >"$work/mixed-answers.json" <<'JSON'
{
  "stack": ["node-tooling"],
  "hasScreens": true,
  "defaultBranch": "trunk",
  "commands": {
    "check": "echo \"it's ok\" &&  make  check",
    "verify": "npm run verify",
    "formatCheckStaged": [
      { "glob": "*.ts", "command": "npx prettier --check" },
      { "glob": "*.py", "command": "ruff format --check" }
    ]
  },
  "testCommands": ["npm test"],
  "ciAllowlist": [".github/workflows/release check.yml", ".github/workflows/it's.yml"]
}
JSON
out=$(run write "$r" "$work/mixed-answers.json")
assert_exit 0 test -f "$r/.claude/dev-workflow.json"
assert_exit 0 sh "$PF" validate "$r/.claude/dev-workflow.json"
assert_exit 0 test "$(jq -r .pluginVersion "$r/.claude/dev-workflow.json")" = "$VERSION"
assert_exit 0 test "$(jq -r .schemaVersion "$r/.claude/dev-workflow.json")" = 1
assert_exit 0 test "$(jq -r '.commands.formatCheckStaged[1].command' "$r/.claude/dev-workflow.json")" = "ruff format --check"
env=$r/.githooks/dev-workflow.env
assert_exit 0 test "$(env_value "$env" DW_FORMATTERS)" = "$(printf '*.ts|npx prettier --check\n*.py|ruff format --check')"
assert_exit 0 test "$(env_value "$env" DW_CHECK)" = "echo \"it's ok\" &&  make  check"
assert_exit 0 test "$(env_value "$env" DW_DEFAULT_BRANCH)" = trunk
assert_exit 0 test "$(env_value "$env" DW_CI_ALLOWLIST)" = "$(printf ".github/workflows/release check.yml\n.github/workflows/it's.yml")"
assert_exit 0 sh -n "$env"
assert_contains "$out" '"path":".claude/dev-workflow.json"'
assert_contains "$out" '"path":".githooks/dev-workflow.env"'
# In the form Prettier prints: a short list on its key's line, a long one a line an item.
pf_text=$(cat "$r/.claude/dev-workflow.json")
assert_contains "$pf_text" '
  "stack": ["node-tooling"],
'
assert_contains "$pf_text" '
  "ciAllowlist": [
    ".github/workflows/release check.yml",
    ".github/workflows/it'"'"'s.yml"
  ]
}'

# A rerun with the same answers is byte-identical, and says so.
cp "$r/.claude/dev-workflow.json" "$work/mixed-pf"
cp "$env" "$work/mixed-env"
out=$(run write "$r" "$work/mixed-answers.json")
assert_file_same "$r/.claude/dev-workflow.json" "$work/mixed-pf"
assert_file_same "$env" "$work/mixed-env"
assert_exit 0 test "$(printf '%s\n' "$out" | jq -r .action | sort -u)" = keep

# --- the env file always sets all four keys, even with empty lists

r=$work/empty-lists
mkdir -p "$r"
printf '{"commands": {"check": "make check"}}\n' >"$work/empty-answers.json"
run write "$r" "$work/empty-answers.json" >/dev/null
env=$r/.githooks/dev-workflow.env
for key in DW_DEFAULT_BRANCH DW_CHECK DW_CI_ALLOWLIST DW_FORMATTERS; do
  assert_exit 0 grep -q "^$key=" "$env"
done
assert_exit 0 test "$(env_value "$env" DW_DEFAULT_BRANCH)" = main
# shellcheck disable=SC2016 # The dollars are the inner shell's.
assert_exit 0 env -i sh -c '. "$1" && [ -n "${DW_FORMATTERS+set}" ] && [ -z "$DW_FORMATTERS" ]' sh "$env"

# --- an existing file, such as one holding only the ledger, is merged into

r=$work/merge
mkdir -p "$r/.claude"
printf '{"managed": {"AGENTS.md#workflow": "abc"}}\n' >"$r/.claude/dev-workflow.json"
run write "$r" "$work/empty-answers.json" >/dev/null
assert_exit 0 test "$(jq -r '.managed["AGENTS.md#workflow"]' "$r/.claude/dev-workflow.json")" = abc
assert_exit 0 test "$(jq -r '.commands.check' "$r/.claude/dev-workflow.json")" = "make check"
# Known keys come first, the ledger last.
assert_exit 0 test "$(jq -r 'keys_unsorted | first + " " + last' "$r/.claude/dev-workflow.json")" = "schemaVersion managed"
# Answers that leave a field out keep its value.
printf '{"hasScreens": true}\n' >"$work/partial.json"
run write "$r" "$work/partial.json" >/dev/null
assert_exit 0 test "$(jq -r '.commands.check, .hasScreens' "$r/.claude/dev-workflow.json" | tr '\n' ' ')" = "make check true "

# --- invalid answers write nothing

r=$work/bad
mkdir -p "$r"
printf '{"commands": {"verify": "x"}}\n' >"$work/bad-answers.json"
assert_exit 2 sh "$PF" write "$r" "$work/bad-answers.json"
assert_contains "$(sh "$PF" write "$r" "$work/bad-answers.json" 2>&1)" "commands.check"
assert_exit 1 test -e "$r/.claude"
assert_exit 1 test -e "$r/.githooks"
printf '{"commands": {"check": "x", "formatCheckStaged": [{"glob": "*.{js,ts}", "command": "x --check"}]}}\n' >"$work/bad-answers.json"
assert_exit 2 sh "$PF" write "$r" "$work/bad-answers.json"
assert_exit 1 test -e "$r/.claude"
printf '{ nope\n' >"$work/bad-answers.json"
assert_exit 2 sh "$PF" write "$r" "$work/bad-answers.json"
printf '{"schemaVersion": 1, "commands": {"check": "x"}}\n' >"$work/bad-answers.json"
assert_exit 2 sh "$PF" write "$r" "$work/bad-answers.json"

# --- a stack's reset commands come from its .resets file

stacks=$(tmp_dir)
printf 'npm run db:reset\n\n# a comment\nsupabase db reset\r\n' >"$stacks/fakedb.resets"
r=$work/stack
mkdir -p "$r"
printf '{"stack": ["node-tooling", "fakedb"], "commands": {"check": "x"}, "databaseResetCommands": ["make reset", "npm run db:reset"]}\n' >"$work/stack-answers.json"
DW_STACKS_DIR=$stacks run write "$r" "$work/stack-answers.json" >/dev/null
assert_exit 0 test "$(jq -c .databaseResetCommands "$r/.claude/dev-workflow.json")" = '["make reset","npm run db:reset","supabase db reset"]'

# --- existing-ci: workflows with per-PR triggers, less the allowlisted ones

r=$work/ci
new_repo "$r"
mkdir -p "$r/.github/workflows/sub"
printf 'on: [push, pull_request]\njobs: {}\n' >"$r/.github/workflows/ci.yml"
printf 'on:\n  pull_request:\n' >"$r/.github/workflows/allowed.yaml"
printf 'on: workflow_dispatch\n' >"$r/.github/workflows/release.yml"
printf 'on: *anchor\n' >"$r/.github/workflows/odd.yml"
printf 'on: push\n' >"$r/.github/workflows/sub/nested.yml"
mkdir -p "$r/.claude"
printf '{"ciAllowlist": [".github/workflows/allowed.yaml"]}\n' >"$r/.claude/dev-workflow.json"
assert_exit 0 test "$(run existing-ci "$r")" = "$(printf '.github/workflows/ci.yml\n.github/workflows/odd.yml')"
assert_exit 0 test -z "$(run existing-ci "$work/empty-lists")"

# --- usage

assert_exit 2 sh "$PF"
assert_exit 2 sh "$PF" write "$work/missing" "$work/empty-answers.json"
assert_exit 2 sh "$PF" write "$work/merge" "$work/missing.json"

# --- a folder that leads out of the project, or a symlinked file, is refused

printf '{"commands": {"check": "true"}}\n' >"$work/escape-answers.json"
for d in .claude .githooks; do
  r=$work/escape-$d
  mkdir -p "$r" "$work/away-$d"
  ln -s "$work/away-$d" "$r/$d"
  assert_exit 2 sh "$PF" write "$r" "$work/escape-answers.json"
  assert_contains "$(sh "$PF" write "$r" "$work/escape-answers.json" 2>&1)" 'outside the project'
  assert_exit 0 test -z "$(ls -A "$work/away-$d")"
  assert_exit 1 test -e "$r/.claude/dev-workflow.json"
done
# A symlinked project file isn't read, even when the env file would be written first.
r=$work/linked-file
mkdir -p "$r/.claude" "$work/away-file"
printf '{"schemaVersion": 1, "pluginVersion": "1.0.0", "commands": {"check": "MARKER-7f3a"}}\n' >"$work/away-file/pf.json"
ln -s "$work/away-file/pf.json" "$r/.claude/dev-workflow.json"
assert_exit 2 sh "$PF" write "$r" "$work/escape-answers.json"
assert_not_contains "$(sh "$PF" write "$r" "$work/escape-answers.json" 2>&1)" MARKER
assert_exit 1 test -e "$r/.githooks"
rm "$r/.claude/dev-workflow.json"
mkdir -p "$r/.githooks"
ln -s "$work/away-file/pf.json" "$r/.githooks/dev-workflow.env"
assert_exit 2 sh "$PF" write "$r" "$work/escape-answers.json"
assert_exit 1 test -e "$r/.claude/dev-workflow.json"
