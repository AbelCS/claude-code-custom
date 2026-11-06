#!/bin/sh
# Tests this repo's own setup: its agent instructions, docs, project file and git
# hooks. What the hooks do is tested in tests/githooks/, against their templates.

ROOT=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=tests/lib/assert.sh
. "$ROOT/tests/lib/assert.sh"

# --- CLAUDE.md and AGENTS.md

expected_claude="$(tmp_dir)/CLAUDE.md"
printf '@AGENTS.md\n' >"$expected_claude"
assert_file_same "$ROOT/CLAUDE.md" "$expected_claude"

assert_exit 0 test -f "$ROOT/AGENTS.md"
assert_exit 0 test "$(wc -l <"$ROOT/AGENTS.md")" -lt 200
agents=$(cat "$ROOT/AGENTS.md")
assert_contains "$agents" "Closes #"
# A fresh clone has no hooks until someone runs this.
assert_contains "$agents" "git config core.hooksPath .githooks"
# Without this, the superpowers skill's menu conflicts with the Workflow section.
assert_contains "$agents" "Landing uses \`/dev-workflow:land\`, which replaces the \`finishing-a-development-branch\` menu and follows the Workflow section here"
assert_contains "$agents" "no worktree or question just to protect a running dev server"

# --- docs

spec=docs/superpowers/specs/2026-11-05-dev-workflow-methodology-design.md
assert_exit 0 test -f "$ROOT/$spec"
assert_exit 0 test -f "$ROOT/docs/superpowers/plans/2026-11-05-dev-workflow-methodology.md"
assert_contains "$(cat "$ROOT/docs/decisions.md")" "${spec#docs/}"
# It explains the format and records no run until one has happened.
maintenance=$(cat "$ROOT/docs/maintenance.md")
assert_contains "$maintenance" "YYYY-MM-DD"
assert_exit 1 grep -Eq '^- |[0-9]{4}-[0-9]{2}-[0-9]{2}' "$ROOT/docs/maintenance.md"
# What the live tests saw, with the version they saw it on.
assert_exit 0 grep -Eq 'Claude Code [0-9]+\.[0-9]+\.[0-9]+' "$ROOT/docs/hook-behaviour.md"

# --- .claude/dev-workflow.json

assert_exit 0 jq -e '
  .schemaVersion == 1
  and has("pluginVersion")
  and .stack == []
  and .hasScreens == false
  and .commands.check == "scripts/check"
  and .commands.verify == "scripts/verify"
' "$ROOT/.claude/dev-workflow.json"

# --- .githooks: the plugin's templates, so that this repo runs what it ships

templates="$ROOT/plugins/dev-workflow/skills/setup/templates/githooks"

# Git silently skips a hook that isn't executable.
for hook in commit-msg pre-commit pre-push; do
  assert_exit 0 test -x "$ROOT/.githooks/$hook"
done

# Any drift from a template is a bug, in whichever copy changed. Listing the templates
# means a new one fails here until it's copied too.
for template in "$templates"/*; do
  assert_file_same "$ROOT/.githooks/$(basename "$template")" "$template"
done
installed=
for file in "$ROOT/.githooks"/*; do
  installed="$installed $(basename "$file")"
done
assert_exit 0 test "$installed" = ' commit-msg dev-workflow.env dw-lib.sh pre-commit pre-push'

# This repo's settings. Its project file above names the same check, it has no
# formatters, and CI runs only for releases.
expected_env="$(tmp_dir)/dev-workflow.env"
cat >"$expected_env" <<'ENV'
DW_DEFAULT_BRANCH=main
DW_CHECK=scripts/check
DW_CI_ALLOWLIST=
DW_FORMATTERS=
ENV
assert_file_same "$ROOT/.githooks/dev-workflow.env" "$expected_env"
