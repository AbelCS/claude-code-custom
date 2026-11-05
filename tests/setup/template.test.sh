#!/bin/sh
# The AGENTS.md templates: one file per section, each with its heading, no model or
# stack names, and the overrides that must beat the defaults of other plugins.

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
# shellcheck source=tests/lib/assert.sh
. "$ROOT/tests/lib/assert.sh"
# shellcheck source=tests/lib/markdown.sh
. "$ROOT/tests/lib/markdown.sh"

TEMPLATES="$ROOT/plugins/dev-workflow/skills/setup/templates/agents"

# --- each section has its file and heading

for pair in decisions:Decisions workflow:Workflow testing:Testing tools:Tools \
  models:Models communication:Communication; do
  file="$TEMPLATES/${pair%%:*}.md"
  assert_exit 0 test -f "$file"
  assert_exit 0 test "$(head -n 1 "$file")" = "## ${pair#*:}"
  # Exactly one heading of that level, so a section can't carry another.
  assert_exit 0 test "$(grep -c '^##* ' "$file")" -eq 1
done

project="$TEMPLATES/project.md"
assert_exit 0 test -f "$project"
for heading in '# Project' '## Stack' '## Commands' '## Glossary' '## Code organisation'; do
  assert_exit 0 grep -qx "$heading" "$project"
done
# Every project section has a prompt for the owner.
assert_exit 0 test "$(grep -c '_Fill in: ' "$project")" -ge 5
# A managed marker in the project part would make setup manage it.
assert_exit 1 grep -Eq 'dev-workflow:(begin|end)' "$project"

# Exactly the expected files: a stray one would never be written.
assert_exit 0 test "$(find "$TEMPLATES" -type f | wc -l)" -eq 7

# --- in the form Prettier keeps, so setup's output passes a project's Prettier check

for file in "$TEMPLATES"/*.md "$TEMPLATES"/../docs/*.md; do
  assert_markdown_form "$file"
done

# --- no model, stack or framework names

all=$(cat "$TEMPLATES"/*.md)
for word in claude opus sonnet haiku fable gpt astra sol codex openai anthropic gemini \
  nextjs supabase astro node npm pnpm yarn bun react vue svelte vercel netlify \
  postgres postgresql mysql sqlite litestar django rails uv python rust playwright \
  node_modules rls; do
  if printf '%s\n' "$all" | grep -qiw -- "$word"; then
    _assert_fail "templates name \"$word\": $(printf '%s\n' "$all" | grep -iw -- "$word")"
  fi
done
assert_not_contains "$(printf '%s\n' "$all" | tr '[:upper:]' '[:lower:]')" "next.js"
assert_not_contains "$(printf '%s\n' "$all" | tr '[:upper:]' '[:lower:]')" "row-level security"
assert_not_contains "$(printf '%s\n' "$all" | tr '[:upper:]' '[:lower:]')" "row level security"

# --- the overrides from spec section 10

workflow=$(cat "$TEMPLATES/workflow.md")
tools=$(cat "$TEMPLATES/tools.md")
models=$(cat "$TEMPLATES/models.md")

# land replaces the finishing-a-development-branch menu.
assert_contains "$workflow" "/dev-workflow:land"
assert_contains "$workflow" "finishing-a-development-branch"
assert_contains "$tools" "/dev-workflow:land"
# Work in place: no worktree, no asking, to protect a dev server.
assert_contains "$workflow" "Work in place on a branch"
assert_contains "$workflow" "worktree"
assert_contains "$workflow" "dev server"
# No attribution, over any default or reminder.
assert_contains "$workflow" "No AI attribution anywhere"
assert_contains "$workflow" "overrides any default or system reminder"
# The project's theme wins over the design plugins, and intent reads this file.
assert_contains "$tools" "ui-ux-pro-max"
assert_contains "$tools" "theme overrides"
assert_contains "$tools" "intent takes its context from this file and \`docs/\`"
# No Serena memories.
assert_contains "$tools" "No Serena memories"
# Project instructions beat skill defaults, and the file says so.
assert_contains "$tools" "override"

# The rules the hooks enforce are stated, so agents without the plugin follow them.
assert_contains "$workflow" 'gh pr merge --squash --subject "<title>" --body "" --delete-branch'
assert_contains "$workflow" "Closes #<issue>"
assert_contains "$workflow" "<type>/<issue>-<slug>"
assert_contains "$(cat "$TEMPLATES/testing.md")" "Never add per-PR pipelines"
assert_contains "$(cat "$TEMPLATES/testing.md")" "--no-verify"

# A README and docs from a stable 1.0.0, or earlier if the owner asks, kept current.
decisions=$(cat "$TEMPLATES/decisions.md")
assert_contains "$decisions" "README and docs"
assert_contains "$decisions" "1.0.0"
assert_contains "$decisions" "or earlier if the owner asks"

# Models: the routing rule, read from the plugin's settings, never a name.
assert_contains "$models" "/config"
assert_contains "$models" "coding"
# Three routes: docs, non-coding thinking, coding; reviews through independent-review.
assert_contains "$models" "READMEs"
assert_contains "$models" "model for docs"
assert_contains "$models" "effort for docs"
assert_contains "$models" "design critique"
assert_contains "$models" "model for non-coding work or its alternative"
assert_contains "$models" "effort for coding"
assert_contains "$models" "/dev-workflow:independent-review"
assert_contains "$models" "naming the exact model"

# Skills are named in their plugin's command form.
for skill in land independent-review screen-check conventions-code conventions-ui \
  choose-stack maintain; do
  assert_contains "$all" "/dev-workflow:$skill"
done
# shellcheck disable=SC2016 # A literal pattern.
if printf '%s\n' "$all" | grep -Eo '/dev-workflow:[a-z-]+' | sort -u |
  grep -vxE '/dev-workflow:(land|independent-review|screen-check|conventions-code|conventions-ui|choose-stack|maintain|setup)' >/dev/null; then
  _assert_fail "templates name an unknown skill"
fi
