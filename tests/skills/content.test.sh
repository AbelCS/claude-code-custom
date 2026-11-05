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

# --- what each skill's rules must say, one "skill|text" a line

while IFS='|' read -r skill needle; do
  [ -n "$skill" ] || continue
  [ -f "$SKILLS/$skill/SKILL.md" ] || _assert_fail "no skill $skill"
  case "$(text "$skill")" in
    *"$needle"*) ;;
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
TABLE
