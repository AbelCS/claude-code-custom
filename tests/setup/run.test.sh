#!/bin/sh
# run.sh --root <dir> --answers <file> --plan|--apply: setup's whole write step.
# gh and claude are stubs: nothing here calls GitHub or installs a plugin.

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
# shellcheck source=tests/lib/assert.sh
. "$ROOT/tests/lib/assert.sh"

RUN="$ROOT/plugins/dev-workflow/scripts/setup/run.sh"
LEGACY="$ROOT/plugins/dev-workflow/skills/setup/references/legacy"
work=$(tmp_dir)

# A hooks path in this machine's git config must not change a result.
GIT_CONFIG_GLOBAL=$work/gitconfig
GIT_CONFIG_NOSYSTEM=1
: >"$GIT_CONFIG_GLOBAL"
export GIT_CONFIG_GLOBAL GIT_CONFIG_NOSYSTEM

# --- stubs: gh signed in, Claude Code new enough, every plugin installed

stubs=$work/stubs
mkdir -p "$stubs"
cat >"$stubs/gh" <<EOF
#!/bin/sh
printf 'gh %s\n' "\$*" >>"$work/calls"
case "\$*" in
  "auth status") exit 0 ;;
  *PATCH*) exit 0 ;;
  "api repos/"*) printf '%s\n' '{"permissions": {"admin": true}, "allow_squash_merge": true, "allow_merge_commit": true,
    "allow_rebase_merge": true, "squash_merge_commit_title": "COMMIT_OR_PR_TITLE",
    "squash_merge_commit_message": "COMMIT_MESSAGES", "delete_branch_on_merge": false}' ;;
  *) exit 1 ;;
esac
EOF
cat >"$stubs/claude" <<EOF
#!/bin/sh
printf 'claude %s\n' "\$*" >>"$work/calls"
[ "\$1" = --version ] && echo "\${CLAUDE_VERSION:-2.1.300} (Claude Code)"
exit 0
EOF
chmod +x "$stubs/gh" "$stubs/claude"
export DW_GH="$stubs/gh" DW_CLAUDE="$stubs/claude"
: >"$work/calls"

config=$work/config
sp=$work/superpowers
for s in brainstorming writing-plans test-driven-development systematic-debugging \
  verification-before-completion receiving-code-review finishing-a-development-branch; do
  mkdir -p "$sp/skills/$s" && : >"$sp/skills/$s/SKILL.md"
done
mkdir -p "$config/plugins"
registry() { # <plugin ids...>: installed for every project
  jq -n --arg sp "$sp" '{version: 2, plugins: ($ARGS.positional
    | map({key: ., value: [{scope: "user", installPath: $sp}]}) | from_entries)}' --args "$@" \
    >"$config/plugins/installed_plugins.json"
}
registry superpowers@claude-plugins-official context7@claude-plugins-official serena@claude-plugins-official \
  intent@intent ui-ux-pro-max@ui-ux-pro-max-skill
export CLAUDE_CONFIG_DIR="$config"

answers=$work/answers.json
printf '{"stack": [], "hasScreens": false, "commands": {"check": "true"}}\n' >"$answers"

# tree_hash <dir>: every path, its kind, mode and content, and the repo's own config.
tree_hash() {
  (
    cd "$1" || exit 1
    find . -path ./.git -prune -o -print | LC_ALL=C sort | while IFS= read -r p; do
      if [ -L "$p" ]; then
        printf 'L %s\n' "$p"
      elif [ -d "$p" ]; then
        printf 'D %s\n' "$p"
      else
        x=-
        [ ! -x "$p" ] || x=x
        printf 'F %s %s %s\n' "$p" "$x" "$(cksum <"$p")"
      fi
    done
    git config --local --list 2>/dev/null
  ) | cksum
}

run() { # <root> <plan|apply> [answers]: the JSON lines, failing unless exit 0
  _out=$(sh "$RUN" --root "$1" --answers "${3:-$answers}" "--$2" 2>"$work/stderr") ||
    _assert_fail "run.sh --$2 $1 failed:
$_out
$(cat "$work/stderr")"
  printf '%s\n' "$_out" | jq -e -s 'length > 0 and all(.[]; (.path | type) == "string" and
    (.action | IN("create", "update", "keep", "conflict")) and (.detail | type) == "string")' >/dev/null ||
    _assert_fail "not one JSON line per path:
$_out"
  printf '%s\n' "$_out"
}

action() { # <json lines> <path>
  printf '%s\n' "$1" | jq -r --arg p "$2" 'select(.path == $p) | .action'
}

# --- an empty repo: plan writes nothing, apply writes all of section 7, step 5

r=$work/empty
new_repo "$r"
before=$(tree_hash "$r")
plan=$(run "$r" plan)
assert_exit 0 test "$(tree_hash "$r")" = "$before"
assert_exit 0 test -z "$(git -C "$r" status --porcelain)"
for p in CLAUDE.md AGENTS.md#project AGENTS.md#workflow .claude/dev-workflow.json .githooks/pre-push \
  .claude/settings.json docs/decisions.md docs/maintenance.md docs/superpowers/specs docs/superpowers/plans; do
  assert_exit 0 test "$(action "$plan" "$p")" = create
done
assert_exit 0 test "$(action "$plan" core.hooksPath)" = update

applied=$(run "$r" apply)
# The plan said what apply did.
assert_exit 0 test "$plan" = "$applied"
printf '@AGENTS.md\n' >"$work/import"
assert_file_same "$r/CLAUDE.md" "$work/import"
for s in decisions workflow testing tools models communication; do
  assert_contains "$(cat "$r/AGENTS.md")" "<!-- dev-workflow:begin $s -->"
done
assert_contains "$(cat "$r/AGENTS.md")" '# Project'
for d in docs/superpowers/specs docs/superpowers/plans; do assert_exit 0 test -d "$r/$d"; done
for f in docs/decisions.md docs/maintenance.md .githooks/dev-workflow.env .githooks/dw-lib.sh; do
  assert_exit 0 test -f "$r/$f"
done
for h in pre-commit commit-msg pre-push; do assert_exit 0 test -x "$r/.githooks/$h"; done
assert_exit 0 test "$(git -C "$r" config core.hooksPath)" = .githooks
assert_exit 0 sh "$ROOT/plugins/dev-workflow/scripts/setup/project-file.sh" validate "$r/.claude/dev-workflow.json"
assert_exit 0 test "$(jq -c .attribution "$r/.claude/settings.json")" = '{"commit":"","pr":"","sessionUrl":false}'
# Approved-only items aren't done without approval.
assert_exit 1 test -e "$r/.claude/settings.local.json"
assert_not_contains "$(cat "$work/calls")" PATCH
assert_not_contains "$(cat "$work/calls")" 'plugin install'

# A rerun reports only keep, and changes nothing.
before=$(tree_hash "$r")
again=$(run "$r" apply)
assert_exit 0 test "$(printf '%s\n' "$again" | jq -r .action | sort -u)" = keep
assert_exit 0 test "$(tree_hash "$r")" = "$before"

# --- CLAUDE.md holding only an old block, with no AGENTS.md: the prompts are written

r=$work/old
new_repo "$r"
for f in "$LEGACY"/web-6.*.md; do cat "$f" && echo; done >"$r/CLAUDE.md"
printf 'x\n' >"$r/app.txt"
git -C "$r" add -A && git -C "$r" commit -qm "chore: start"
before=$(tree_hash "$r")
plan=$(run "$r" plan)
assert_exit 0 test "$(tree_hash "$r")" = "$before"
assert_exit 0 test -z "$(git -C "$r" status --porcelain)"
applied=$(run "$r" apply)
assert_exit 0 test "$plan" = "$applied"
assert_exit 0 test "$(action "$applied" AGENTS.md#project)" = create
assert_contains "$(cat "$r/AGENTS.md")" '# Project'
assert_contains "$(cat "$r/AGENTS.md")" '<!-- dev-workflow:begin workflow -->'
assert_not_contains "$(cat "$r/AGENTS.md")" 'Web Dev Workflow Rules'
assert_file_same "$r/CLAUDE.md" "$work/import"
before=$(tree_hash "$r")
again=$(run "$r" apply)
assert_exit 0 test "$(printf '%s\n' "$again" | jq -r .action | sort -u)" = keep
assert_exit 0 test "$(tree_hash "$r")" = "$before"

# CLAUDE.md with the project's own text as well: moved, and not given the prompts.
r=$work/own
new_repo "$r"
{ printf '# Our app\n\nIt does one thing.\n\n' && cat "$LEGACY/issues.md"; } >"$r/CLAUDE.md"
run "$r" apply >/dev/null
assert_contains "$(cat "$r/AGENTS.md")" 'It does one thing.'
assert_not_contains "$(cat "$r/AGENTS.md")" '_Fill in:'
assert_not_contains "$(cat "$r/AGENTS.md")" 'GitHub Issue-Driven Workflow'

# --- a path with spaces, run from a subfolder

r="$work/with space/repo"
new_repo "$r"
mkdir -p "$r/sub dir"
out=$(cd "$r/sub dir" && sh "$RUN" --root . --answers "$answers" --apply 2>&1) || _assert_fail "from a subfolder: $out"
assert_exit 0 test -f "$r/AGENTS.md"
assert_exit 0 test -x "$r/.githooks/pre-push"
assert_exit 1 test -e "$r/sub dir/AGENTS.md"
assert_exit 0 test "$(git -C "$r" config core.hooksPath)" = .githooks

# --- a worktree, where .git is a file: the hooks are on, and reject a bad commit

main=$work/main
new_repo "$main"
git -C "$main" commit -q --allow-empty -m "chore: start"
git -C "$main" worktree add -q -b feat/1-x "$work/wt" 2>/dev/null || _assert_fail "no worktree"
assert_exit 0 test -f "$work/wt/.git"
run "$work/wt" apply >/dev/null
assert_exit 0 test -x "$work/wt/.githooks/commit-msg"
assert_exit 0 test "$(git -C "$work/wt" config core.hooksPath)" = .githooks
git -C "$work/wt" add -A
assert_exit 1 git -C "$work/wt" commit -qm "bad message"
assert_exit 0 git -C "$work/wt" commit -qm "chore: set up (#1)"

# --- approvals: the merge permission, GitHub settings and missing plugins

r=$work/approved
new_repo "$r"
git -C "$r" remote add origin https://github.com/o/r.git
registry superpowers@claude-plugins-official context7@claude-plugins-official
jq '. + {approvals: {githubSettings: true, mergePermission: true, installPlugins: true}}' "$answers" >"$work/approved.json"
: >"$work/calls"
plan=$(run "$r" plan "$work/approved.json")
assert_exit 0 test "$(action "$plan" github:o/r)" = update
assert_exit 0 test "$(action "$plan" plugin:serena)" = create
# No screens: the plugins only screens need aren't installed.
assert_exit 0 test -z "$(action "$plan" plugin:intent)"
assert_not_contains "$(cat "$work/calls")" PATCH
assert_not_contains "$(cat "$work/calls")" 'plugin install'
run "$r" apply "$work/approved.json" >/dev/null
assert_contains "$(cat "$work/calls")" 'PATCH repos/o/r'
assert_contains "$(cat "$work/calls")" 'claude plugin install serena@claude-plugins-official'
assert_contains "$(jq -c .permissions.allow "$r/.claude/settings.local.json")" 'Bash(gh pr merge *)'
registry superpowers@claude-plugins-official context7@claude-plugins-official serena@claude-plugins-official \
  intent@intent ui-ux-pro-max@ui-ux-pro-max-skill

# --- hooks in .git/hooks: a conflict, and the hooks left off, unless moving them is approved

r=$work/git-hooks
new_repo "$r"
printf '#!/bin/sh\n' >"$r/.git/hooks/pre-push"
chmod +x "$r/.git/hooks/pre-push"
plan=$(run "$r" plan)
assert_exit 0 test "$(action "$plan" .git/hooks)" = conflict
assert_exit 0 test -z "$(action "$plan" core.hooksPath)"
run "$r" apply >/dev/null
assert_exit 1 git -C "$r" config core.hooksPath
jq '. + {approvals: {moveGitHooks: true}}' "$answers" >"$work/move.json"
plan=$(run "$r" plan "$work/move.json")
assert_exit 0 test "$(action "$plan" .git/hooks/pre-push)" = update
assert_exit 0 test -x "$r/.git/hooks/pre-push"
run "$r" apply "$work/move.json" >/dev/null
assert_exit 0 test -x "$r/.githooks/pre-push.local"
assert_exit 0 test "$(git -C "$r" config core.hooksPath)" = .githooks

# --- CLAUDE.md as a symlink

# To AGENTS.md: the plan, worked out on a copy, still sees it as AGENTS.md.
r=$work/claude-link
new_repo "$r"
printf '# Ours\n\nKept.\n' >"$r/AGENTS.md"
ln -s AGENTS.md "$r/CLAUDE.md"
before=$(tree_hash "$r")
plan=$(run "$r" plan)
assert_exit 0 test "$(tree_hash "$r")" = "$before"
assert_exit 0 test "$(action "$plan" CLAUDE.md)" = update
applied=$(run "$r" apply)
assert_exit 0 test "$plan" = "$applied"
assert_exit 1 test -L "$r/CLAUDE.md"
assert_file_same "$r/CLAUDE.md" "$work/import"
assert_contains "$(cat "$r/AGENTS.md")" 'Kept.'

# Outside the repo: the plan shows a conflict, and nothing is read or written.
mkdir -p "$work/private"
printf 'MARKER-PRIVATE-KEY-7f3a\n' >"$work/private/key"
cp "$work/private/key" "$work/private-before"
r=$work/claude-outside
new_repo "$r"
printf '# Ours\n' >"$r/AGENTS.md"
ln -s "$work/private/key" "$r/CLAUDE.md"
before=$(tree_hash "$r")
plan=$(run "$r" plan)
assert_exit 0 test "$(tree_hash "$r")" = "$before"
assert_exit 0 test "$(action "$plan" CLAUDE.md)" = conflict
assert_contains "$(printf '%s\n' "$plan" | jq -r 'select(.path == "CLAUDE.md") | .detail')" 'resolve it by hand'
assert_exit 0 test -z "$(action "$plan" AGENTS.md)"
assert_not_contains "$plan" MARKER-PRIVATE-KEY
# Apply stops before writing anything.
assert_exit 2 sh "$RUN" --root "$r" --answers "$answers" --apply
assert_contains "$(sh "$RUN" --root "$r" --answers "$answers" --apply 2>&1)" 'a link to somewhere other than AGENTS.md'
assert_exit 0 test "$(tree_hash "$r")" = "$before"
assert_not_contains "$(cat "$r/AGENTS.md")" MARKER-PRIVATE-KEY
assert_exit 0 test -L "$r/CLAUDE.md"
assert_file_same "$work/private/key" "$work/private-before"

# --- a folder setup writes in that leads out of the repo is refused

for d in .claude .githooks docs; do
  r=$work/escape-$d
  new_repo "$r"
  mkdir -p "$work/away-$d"
  ln -s "$work/away-$d" "$r/$d"
  before=$(tree_hash "$r")
  for m in plan apply; do
    assert_exit 2 sh "$RUN" --root "$r" --answers "$answers" "--$m"
    assert_contains "$(sh "$RUN" --root "$r" --answers "$answers" "--$m" 2>&1)" "$d"
  done
  assert_exit 0 test "$(tree_hash "$r")" = "$before"
  assert_exit 0 test -z "$(ls -A "$work/away-$d")"
done

# --- stops before writing anything

# Claude Code older than the minimum.
r=$work/old-claude
new_repo "$r"
before=$(tree_hash "$r")
assert_exit 1 env CLAUDE_VERSION=2.1.294 sh "$RUN" --root "$r" --answers "$answers" --apply
assert_contains "$(CLAUDE_VERSION=2.1.294 sh "$RUN" --root "$r" --answers "$answers" --apply 2>&1)" '2.1.295'
assert_exit 0 test "$(tree_hash "$r")" = "$before"

# Answers the project file refuses, or an approval it doesn't know.
printf '{"commands": {}}\n' >"$work/bad.json"
assert_exit 2 sh "$RUN" --root "$r" --answers "$work/bad.json" --apply
printf '{"commands": {"check": "true"}, "approvals": {"mergePermision": true}}\n' >"$work/typo.json"
assert_exit 2 sh "$RUN" --root "$r" --answers "$work/typo.json" --apply
assert_exit 0 test "$(tree_hash "$r")" = "$before"

# An AGENTS.md symlink is refused before the project file is written.
ln -s elsewhere.md "$r/AGENTS.md"
assert_exit 2 sh "$RUN" --root "$r" --answers "$answers" --apply
assert_exit 1 test -e "$r/.claude"
rm "$r/AGENTS.md"

assert_exit 2 sh "$RUN" --root "$r" --answers "$answers"
assert_exit 2 sh "$RUN" --root "$work/nowhere" --answers "$answers" --plan
echo "run: ok"
