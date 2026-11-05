#!/bin/sh
# The plugin's skills. Every skill: frontmatter this test and Claude Code can read,
# a name matching its folder, a short description, a body under 500 lines, the
# reference files it names, and no model, framework or database names. Then, per
# skill, the strings its rules must contain, from the table below.

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
# shellcheck source=tests/lib/assert.sh
. "$ROOT/tests/lib/assert.sh"

SKILLS="$ROOT/plugins/dev-workflow/skills"

# frontmatter <file>: the lines between the opening and closing ---, or exit 1 if
# the file doesn't start with one or never closes it.
frontmatter() {
  awk '
    NR == 1 { if ($0 != "---") exit 1; next }
    $0 == "---" { closed = 1; exit }
    { print }
    END { if (!closed) exit 1 }
  ' "$1"
}

# body <file>: everything after the frontmatter.
body() {
  awk 'NR == 1 { next } !done && $0 == "---" { done = 1; next } done' "$1"
}

# text <skill>: the skill and its reference files, which is what its rules can be in.
text() {
  cat "$SKILLS/$1/SKILL.md"
  [ ! -d "$SKILLS/$1/references" ] || find "$SKILLS/$1/references" -type f -name '*.md' -exec cat {} +
}

# --- every skill

found=0
for file in "$SKILLS"/*/SKILL.md; do
  [ -f "$file" ] || continue
  found=$((found + 1))
  dir=$(dirname "$file")
  skill=$(basename "$dir")

  head=$(frontmatter "$file") || _assert_fail "$skill: SKILL.md has no frontmatter between --- lines"

  # One plain "key: value" a line, with keys Claude Code knows. A value holding
  # ": " or " #", or starting with a YAML indicator, would not parse as a plain
  # string, and a skill whose YAML doesn't parse loads with no fields set.
  printf '%s\n' "$head" | awk -v skill="$skill" '
    BEGIN {
      split("name description when_to_use argument-hint arguments disable-model-invocation user-invocable allowed-tools disallowed-tools model effort context agent paths", k, " ")
      for (i in k) known[k[i]] = 1
    }
    {
      if ($0 !~ /^[a-z_-]+: [^ ]/) { printf "%s: frontmatter line not \"key: value\": %s\n", skill, $0; bad = 1; next }
      key = $0; sub(/:.*/, "", key)
      value = $0; sub(/^[a-z_-]+: /, "", value)
      if (!(key in known)) { printf "%s: unknown frontmatter key: %s\n", skill, key; bad = 1 }
      if (key in seen) { printf "%s: frontmatter key twice: %s\n", skill, key; bad = 1 }
      seen[key] = 1
      if (value ~ /: / || value ~ / #/ || value ~ /:$/) { printf "%s: %s holds \": \" or \" #\", so it is not a plain YAML string\n", skill, key; bad = 1 }
    }
    END { exit bad }
  ' >&2 || _assert_fail "$skill: frontmatter isn't plain YAML Claude Code can read"
  while IFS= read -r line; do
    case "${line#*: }" in
      [][{}\&*!\|\>%@\`\"\'\,?#-]*) _assert_fail "$skill: ${line%%:*} starts with a YAML indicator" ;;
    esac
  done <<HEAD
$head
HEAD

  name=$(printf '%s\n' "$head" | sed -n 's/^name: //p')
  [ "$name" = "$skill" ] || _assert_fail "$skill: name is \"$name\", not its folder's name"

  description=$(printf '%s\n' "$head" | sed -n 's/^description: //p')
  [ -n "$description" ] || _assert_fail "$skill: no description"
  length=$(printf '%s' "$description" | wc -m | tr -d ' ')
  [ "$length" -lt 300 ] || _assert_fail "$skill: description is $length characters, not under 300"

  lines=$(body "$file" | wc -l | tr -d ' ')
  [ "$lines" -lt 500 ] || _assert_fail "$skill: body is $lines lines, not under 500"

  # Every reference file the body names is there.
  refs=$(grep -o 'references/[A-Za-z0-9_./-]*[A-Za-z0-9_-]' "$file" | sort -u)
  while IFS= read -r ref; do
    [ -z "$ref" ] || [ -e "$dir/$ref" ] || _assert_fail "$skill: names $ref, which doesn't exist"
  done <<REFS
$refs
REFS

  # Model names live in plugin.json and the README; skills read settings.
  all=$(text "$skill")
  for word in opus sonnet haiku fable gpt astra sol gemini; do
    if printf '%s\n' "$all" | grep -qiw -- "$word"; then
      _assert_fail "$skill names the model \"$word\": $(printf '%s\n' "$all" | grep -iw -- "$word")"
    fi
  done
  if printf '%s\n' "$all" | grep -Eqi 'claude-[a-z]+-[0-9]|gpt-[0-9]'; then
    _assert_fail "$skill names a model id: $(printf '%s\n' "$all" | grep -Ei 'claude-[a-z]+-[0-9]|gpt-[0-9]')"
  fi

  # Framework and database wording lives in stacks/, apart from the general
  # "with or without row-level security" rule.
  for word in nextjs supabase astro react vue svelte angular vercel netlify postgres \
    postgresql mysql sqlite litestar django rails prisma drizzle tailwind shadcn rls; do
    if printf '%s\n' "$all" | grep -qiw -- "$word"; then
      _assert_fail "$skill names \"$word\": $(printf '%s\n' "$all" | grep -iw -- "$word")"
    fi
  done
  lower=$(printf '%s\n' "$all" | tr '[:upper:]' '[:lower:]' | sed 's/with or without row-level security//g')
  for phrase in "next.js" "row-level security" "row level security"; do
    assert_not_contains "$lower" "$phrase"
  done
done
[ "$found" -gt 0 ] || _assert_fail "no skills found in $SKILLS"

# --- skills only a person starts: Claude never loads them on its own

for skill in maintain enable-releases; do
  file="$SKILLS/$skill/SKILL.md"
  [ -f "$file" ] || _assert_fail "no skill $skill"
  frontmatter "$file" | grep -qx 'disable-model-invocation: true' ||
    _assert_fail "$skill doesn't have disable-model-invocation: true"
done

# --- enable-releases' templates: the release runs by hand, and the optional check only
# on release-please's pull requests, read with the same detector pre-commit uses

TEMPLATES="$SKILLS/enable-releases/templates"
# shellcheck source=plugins/dev-workflow/skills/setup/templates/githooks/dw-lib.sh
. "$ROOT/plugins/dev-workflow/skills/setup/templates/githooks/dw-lib.sh"
for t in release-please.yml release-check.yml release-please-config.json release-please-manifest.json; do
  [ -f "$TEMPLATES/$t" ] || _assert_fail "enable-releases has no template $t"
done
release=$(cat "$TEMPLATES/release-please.yml")
assert_contains "$release" "workflow_dispatch"
triggers=$(dw_ci_triggers "$release") || _assert_fail "the trigger detector failed on release-please.yml"
[ -z "$triggers" ] || _assert_fail "release-please.yml has the per-PR triggers: $triggers"
assert_contains "$release" "googleapis/release-please-action@"
check=$(cat "$TEMPLATES/release-check.yml")
triggers=$(dw_ci_triggers "$check") || _assert_fail "the trigger detector failed on release-check.yml"
[ "$triggers" = pull_request ] || _assert_fail "release-check.yml should run on pull_request alone, not: $triggers"
assert_contains "$check" "if: startsWith(github.head_ref, 'release-please--')"
for t in release-please-config.json release-please-manifest.json; do
  jq -e . "$TEMPLATES/$t" >/dev/null 2>&1 || _assert_fail "$t isn't JSON"
done

# --- what each skill's rules must say, one "skill|text" a line, in any capitals, so
# a rule can start a sentence

lowered() { tr '[:upper:]' '[:lower:]'; }

while IFS='|' read -r skill needle; do
  [ -n "$skill" ] || continue
  [ -f "$SKILLS/$skill/SKILL.md" ] || _assert_fail "no skill $skill"
  case "$(text "$skill" | lowered)" in
    *"$(printf '%s' "$needle" | lowered)"*) ;;
    *) _assert_fail "$skill doesn't say: $needle" ;;
  esac
done <<'TABLE'
land|gh pr merge <n> --squash --subject "<title>" --body "" --delete-branch
land|--squash
land|--body ""
land|--delete-branch
land|Closes #
land|asks first only for a change the owner hasn't approved
land|money rules or permissions
land|as its own command
land|Never chain
land|If a merge is blocked, stop and ask
land|never work around it
land|finishing-a-development-branch
land|verification-before-completion
land|/security-review
land|/dev-workflow:independent-review
land|/dev-workflow:screen-check
land|${user_config.review_threshold_lines}
land|acceptance criteria
land|no attribution
land|GitHub MCP
land|placeholder rather than a value
independent-review|${user_config.reviewer_command}
independent-review|${user_config.reviewer_name}
independent-review|Announce
independent-review|before calling it
independent-review|<brief>
independent-review|naming the files
independent-review|receiving-code-review
independent-review|against the code
independent-review|Codex is missing
independent-review|Never skip it silently
independent-review|ask whether to go ahead without it
independent-review|placeholder rather than a value
screen-check|Every screen the change touches
screen-check|light
screen-check|dark
screen-check|360
screen-check|keyboard
screen-check|empty, filled and long
screen-check|If no browser tool is available
screen-check|Never skip it silently
screen-check|Fix what you find before reporting
screen-check|/dev-workflow:conventions-ui
conventions-code|Domain first
conventions-code|glossary
conventions-code|Small, focused files
conventions-code|contracts, queries, actions, tasks, input, rules, labels, ui
conventions-code|stack file
conventions-code|lint errors
conventions-code|depend downwards
conventions-code|never reads the database directly
conventions-code|A query fetches, a pure function shapes
conventions-code|named pure functions with unit tests
conventions-code|real database, signed in as a real role
conventions-code|every row
conventions-code|row limits
conventions-code|page by a unique key
conventions-code|Validate on the server
conventions-code|in the data layer as well as in code
conventions-code|with or without row-level security
conventions-code|Where the database enforces access rules on each row
conventions-code|Where it doesn't
conventions-code|data-access layer
conventions-code|Every new table gets its access rules and a test of them
conventions-code|all or nothing
conventions-code|structured data
conventions-code|append
conventions-code|only through migrations
conventions-code|Never reset the owner's local database without asking
conventions-code|work in place
conventions-code|parity test
conventions-ui|Short labels
conventions-ui|Never say it twice
conventions-ui|(optional)
conventions-ui|Reread every string
conventions-ui|design system
conventions-ui|showcase
conventions-ui|Theme tokens only
conventions-ui|One type scale
conventions-ui|reduced motion
conventions-ui|one helper
conventions-ui|4.5:1
conventions-ui|3:1
conventions-ui|visible focus
conventions-ui|accessible names
conventions-ui|never colour alone
conventions-ui|menu equivalent for drag and drop
conventions-ui|skip link
conventions-ui|screen-reader summary
conventions-ui|hand cursor
conventions-ui|`title`
conventions-ui|360
conventions-ui|16 px
conventions-ui|40 px
conventions-ui|loading skeleton
conventions-ui|connection error
conventions-ui|project's own theme
conventions-ui|/dev-workflow:screen-check
choose-stack|where it runs
choose-stack|who operates it
choose-stack|data limits
choose-stack|licences
choose-stack|PoC
choose-stack|production
choose-stack|No default vendor
choose-stack|One question at a time
choose-stack|recommendation first
choose-stack|current stable versions
choose-stack|Context7
choose-stack|docs/superpowers/specs/
choose-stack|docs/decisions.md
choose-stack|${CLAUDE_PLUGIN_ROOT}/stacks/
setup|/dev-workflow:choose-stack
setup|${CLAUDE_PLUGIN_ROOT}/stacks/<name>.md
setup|only the chosen stacks' files
maintain|clean, updated
maintain|one issue and one squash-merged pull request per area
maintain|verify
maintain|Branches
maintain|Dead code
maintain|Dependencies
maintain|Code smells
maintain|Docs
maintain|Methodology
maintain|${CLAUDE_PLUGIN_ROOT}/scripts/maintain/merged-branches.sh
maintain|git worktree remove
maintain|never --force
maintain|git worktree prune
maintain|List everything else
maintain|deadCode
maintain|If none is configured, say so
maintain|migration guide
maintain|audit
maintain|since the last run
maintain|/simplify
maintain|/code-review
maintain|README
maintain|Finished plans
maintain|met but still open
maintain|run.sh
maintain|docs/maintenance.md
maintain|- YYYY-MM-DD: what was done
maintain|${user_config.maintenance_interval_days}
maintain|money rules or permissions
maintain|placeholder rather than a value
enable-releases|github.com
enable-releases|Conventional Commits
enable-releases|Stop and ask before overwriting
enable-releases|package.json` at the root: `node`
enable-releases|pyproject.toml
enable-releases|setup.py
enable-releases|Cargo.toml
enable-releases|go.mod
enable-releases|composer.json
enable-releases|`simple`
enable-releases|ask which
enable-releases|0.1.0
enable-releases|gh api repos/googleapis/release-please-action/releases/latest
enable-releases|current major version
enable-releases|workflow_dispatch
enable-releases|ciAllowlist
enable-releases|release-please--
enable-releases|GITHUB_TOKEN
enable-releases|Allow GitHub Actions to create and approve pull requests
enable-releases|${CLAUDE_SKILL_DIR}/templates/
enable-releases|Existing workflows
TABLE
