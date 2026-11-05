#!/bin/sh
# Setup, end to end, on the two small real apps in tests/fixtures/, spec section 11: each
# is copied to a temp folder, put in a starting state, and set up with run.sh --apply and
# its answers file, tests/fixtures/<name>.answers.json. Then, for each starting state:
# CLAUDE.md is the import and AGENTS.md has every managed section, any old block is gone,
# a bad commit and a badly formatted file are rejected and a good commit passes, pre-push
# runs the app's real check, which passes, and fails when a test does, a second apply
# changes nothing, and project edits survive a rerun. Each app also runs its database test
# against a database of its own in Docker: row-level security for Next.js with Supabase,
# and the data-access layer for Litestar with Postgres.
#
# It installs the apps' packages and starts containers, so it takes minutes, and lives
# here rather than in scripts/check. Docker not running is a failure that says so.
# DW_SKIP_FIXTURES=1 skips it, saying so. DW_FIXTURES picks some of the fixtures, by name.
#
# gh and claude are stubs, as in tests/setup/run.test.sh: nothing here calls GitHub or
# installs a plugin. The containers are each app's own, named with a dwtest- prefix and
# removed by that exact name; the test fails if any are left.

if [ "${DW_SKIP_FIXTURES:-}" = 1 ]; then
  echo 'fixtures: skipped, because DW_SKIP_FIXTURES=1'
  exit 0
fi

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
# shellcheck source=tests/lib/assert.sh
. "$ROOT/tests/lib/assert.sh"

RUN="$ROOT/plugins/dev-workflow/scripts/setup/run.sh"
SETUP="$ROOT/plugins/dev-workflow/scripts/setup"
LEGACY="$ROOT/plugins/dev-workflow/skills/setup/references/legacy"
FIXTURES="$ROOT/tests/fixtures"
SKIP_HINT='or set DW_SKIP_FIXTURES=1 to skip these tests'

for tool in npm uv docker nc; do
  command -v "$tool" >/dev/null 2>&1 || _assert_fail "fixtures: $tool isn't on the PATH: install it, $SKIP_HINT"
done
docker info >/dev/null 2>&1 || _assert_fail "fixtures: Docker isn't running: start it, $SKIP_HINT"

work=$(tmp_dir)
export NEXT_TELEMETRY_DISABLED=1 UV_NO_PROGRESS=1 npm_config_fund=false npm_config_audit=false

# --- stubs: gh signed in, Claude Code new enough, no plugins installed

stubs=$work/stubs
mkdir -p "$stubs" "$work/config/plugins"
cat >"$stubs/gh" <<'EOF'
#!/bin/sh
[ "$*" = "auth status" ]
EOF
cat >"$stubs/claude" <<'EOF'
#!/bin/sh
[ "$1" = --version ] && echo "2.1.300 (Claude Code)"
exit 0
EOF
chmod +x "$stubs/gh" "$stubs/claude"
export DW_GH="$stubs/gh" DW_CLAUDE="$stubs/claude" CLAUDE_CONFIG_DIR="$work/config"

# --- Docker: what this test may leave, checked before and after

# leftovers: every container, volume and network a fixture names, one a line.
leftovers() {
  docker ps -a --format '{{.Names}}' | grep -E '(^|_)dwtest-'
  docker volume ls --format '{{.Name}}' | grep -E '(^|_)dwtest-'
  docker network ls --format '{{.Name}}' | grep -E '(^|_)dwtest-'
}
# snapshot: every container, volume and network there is, so that the end can tell
# whether anything was left, named or not.
snapshot() {
  { docker ps -aq --no-trunc && docker volume ls -q && docker network ls -q --no-trunc; } | LC_ALL=C sort
}
snapshot >"$work/docker.before" || _assert_fail "fixtures: cannot list Docker's containers, volumes and networks"
found=$(leftovers)
[ -z "$found" ] || _assert_fail "fixtures: Docker already has these, from an earlier run or someone else, so nothing was started:
$found
Each fixture's scripts/db-test.sh says how it removes its own."

# --- helpers

# copy_fixture <name> <dest>: the fixture's files as git would keep them, so nothing
# installed in it comes along.
copy_fixture() {
  mkdir -p "$2"
  (cd "$FIXTURES/$1" && git ls-files --cached --others --exclude-standard) >"$work/files" ||
    _assert_fail "cannot list the files of fixture $1"
  [ -s "$work/files" ] || _assert_fail "fixture $1 has no files"
  while IFS= read -r f; do
    { mkdir -p "$2/$(dirname "$f")" && cp -p "$FIXTURES/$1/$f" "$2/$f"; } || _assert_fail "cannot copy $1/$f"
  done <"$work/files"
}

# start_repo <dir>: a repo holding what's in the folder, in one commit.
start_repo() {
  new_repo "$1"
  { git -C "$1" add -A && git -C "$1" commit -qm "chore: start"; } || _assert_fail "cannot commit the fixture in $1"
}

# tree_hash <dir>: every path, its kind, mode and content, but what's installed or built,
# and the repo's own config.
tree_hash() {
  (
    cd "$1" || exit 1
    find . \( -path ./.git -o -path ./node_modules -o -path ./.next -o -path ./.venv \
      -o -name __pycache__ -o -name .pytest_cache -o -name .ruff_cache \) -prune -o -print |
      LC_ALL=C sort | while IFS= read -r p; do
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

apply() { # <repo> <answers>: run.sh --apply's JSON lines, failing unless it exits 0
  _out=$(sh "$RUN" --root "$1" --answers "$2" --apply 2>"$work/stderr") ||
    _assert_fail "run.sh --apply $1 failed:
$_out
$(cat "$work/stderr")"
  printf '%s\n' "$_out"
}

actions() { # <json lines>: each distinct action, sorted, space-separated
  printf '%s\n' "$1" | jq -r .action | sort -u | tr '\n' ' ' | sed 's/ $//'
}

commit() { # <repo> <message>: commits what's staged, printing the hooks' output
  git -C "$1" commit -q -m "$2" 2>&1
}

# check_setup <repo>: what every starting state ends with, once set up.
check_setup() {
  printf '@AGENTS.md\n' >"$work/import"
  assert_file_same "$1/CLAUDE.md" "$work/import"
  _agents=$(cat "$1/AGENTS.md")
  for _s in decisions workflow testing tools models communication; do
    assert_contains "$_agents" "<!-- dev-workflow:begin $_s -->"
    assert_contains "$_agents" "<!-- dev-workflow:end $_s -->"
  done
  assert_not_contains "$_agents" '## Web Dev Workflow Rules'
  assert_not_contains "$_agents" '## GitHub Issue-Driven Workflow'
  assert_exit 0 test "$(sh "$SETUP/detect.sh" "$1" | jq -c .legacyBlocks)" = '[]'
  assert_exit 0 sh "$SETUP/project-file.sh" validate "$1/.claude/dev-workflow.json"
  assert_exit 0 test "$(git -C "$1" config core.hooksPath)" = .githooks
  for _h in pre-commit commit-msg pre-push; do assert_exit 0 test -x "$1/.githooks/$_h"; done
  assert_exit 0 test "$(jq -c .attribution "$1/.claude/settings.json")" = '{"commit":"","pr":"","sessionUrl":false}'
}

# commits <repo> <bad file> <bad content>: on a work branch, the hooks reject a bad
# message, a missing issue number and a badly formatted file, and pass a good commit.
commits() {
  git -C "$1" switch -q -c feat/1-setup
  git -C "$1" add -A
  _out=$(commit "$1" "set up the workflow") && _assert_fail "a bad message was accepted"
  assert_contains "$_out" 'commit-msg:'
  _out=$(commit "$1" "chore: set up the workflow") && _assert_fail "a missing issue number was accepted"
  assert_contains "$_out" 'commit-msg:'
  _out=$(commit "$1" "chore: set up the workflow (#1)") || _assert_fail "a good commit was rejected:
$_out"
  assert_exit 0 test -z "$(git -C "$1" status --porcelain)"

  printf '%s\n' "$3" >"$1/$2"
  git -C "$1" add -- "$2"
  _out=$(commit "$1" "feat: add a badly formatted file (#1)") && _assert_fail "a badly formatted file was accepted"
  assert_contains "$_out" 'pre-commit:'
  git -C "$1" rm -q --cached -- "$2" && rm -f "$1/$2"
  assert_exit 0 test -z "$(git -C "$1" status --porcelain)"
}

# rerun <repo> <answers>: a second apply says keep for everything and changes nothing.
rerun() {
  _before=$(tree_hash "$1")
  _again=$(apply "$1" "$2")
  assert_exit 0 test "$(actions "$_again")" = keep
  assert_exit 0 test "$(tree_hash "$1")" = "$_before"
}

# push <repo> <passing check text> <file> <breaking edit, a sed script>: pre-push runs
# the real check on a push of the work branch, which passes, then fails once a test does.
push() {
  git init -q --bare "$1.remote.git"
  git -C "$1" remote add origin "$1.remote.git"
  _out=$(git -C "$1" push -q origin feat/1-setup 2>&1) || _assert_fail "the push failed, so the check failed:
$_out"
  assert_contains "$_out" "$2"
  sed "$4" "$1/$3" >"$work/broken" && cat "$work/broken" >"$1/$3"
  git -C "$1" add -- "$3"
  commit "$1" "fix: break a test (#1)" >/dev/null || _assert_fail "cannot commit the broken test"
  _out=$(git -C "$1" push -q origin feat/1-setup 2>&1) && _assert_fail "a failing check let the push through:
$_out"
  assert_contains "$_out" 'pre-push: the check failed'
  git -C "$1" reset -q --hard HEAD~1
}

# edits <repo> <answers>: edits in a managed section, the project's own part of AGENTS.md
# and a hook survive a rerun, which reports the two it doesn't own any more as conflicts.
edits() {
  awk '{ print } /^<!-- dev-workflow:begin workflow -->$/ { print "- Our own rule: deploys wait for Friday." }' \
    "$1/AGENTS.md" >"$work/agents" && cat "$work/agents" >"$1/AGENTS.md"
  printf '\nOur own closing note.\n' >>"$1/AGENTS.md"
  printf '# Our own line.\n' >>"$1/.githooks/pre-commit"
  git -C "$1" add -A
  commit "$1" "docs: add our own rules (#1)" >/dev/null || _assert_fail "cannot commit the project's edits"
  _before=$(tree_hash "$1")
  _again=$(apply "$1" "$2")
  assert_exit 0 test "$(tree_hash "$1")" = "$_before"
  assert_exit 0 test "$(printf '%s\n' "$_again" | jq -r 'select(.action != "keep") | .path' | sort | tr '\n' ' ')" \
    = '.githooks/pre-commit AGENTS.md#workflow '
  assert_exit 0 test "$(printf '%s\n' "$_again" | jq -r 'select(.action != "keep") | .action' | sort -u)" = conflict
  assert_contains "$(cat "$1/AGENTS.md")" 'Our own rule: deploys wait for Friday.'
  assert_contains "$(cat "$1/AGENTS.md")" 'Our own closing note.'
  assert_contains "$(cat "$1/.githooks/pre-commit")" '# Our own line.'
}

# no_docker <repo>: the app's database test, with Docker not running, says so.
no_docker() {
  mkdir -p "$work/no-docker"
  printf '#!/bin/sh\necho "Cannot connect to the Docker daemon" >&2\nexit 1\n' >"$work/no-docker/docker"
  chmod +x "$work/no-docker/docker"
  _out=$(PATH="$work/no-docker:$PATH" sh "$1/scripts/db-test.sh" 2>&1) && _assert_fail "the database test passed without Docker"
  assert_contains "$_out" "Docker isn't running"
}

# no_leftovers <what>: nothing a fixture names is left in Docker, and nothing new at all.
no_leftovers() {
  _left=$(leftovers)
  [ -z "$_left" ] || _assert_fail "$1 left these in Docker:
$_left"
  snapshot >"$work/docker.after" || _assert_fail "cannot list Docker's containers, volumes and networks"
  _new=$(LC_ALL=C comm -13 "$work/docker.before" "$work/docker.after")
  [ -z "$_new" ] || _assert_fail "these are new in Docker since the test started, by ID, after $1. Something
else may have made them, so check what each is before removing anything:
$_new"
}

# old_block <version>: an old Web Dev Workflow Rules block, as published.
old_block() {
  for _f in "$LEGACY"/web-"$1".*.md; do cat "$_f" && echo; done
}

# --- Next.js with Supabase

next_supabase() {
  answers=$FIXTURES/next-supabase.answers.json
  bad_js='export const x = {a:1}'

  # An old block in AGENTS.md, the old CLAUDE.md pointer, and release-please as the old
  # enable-releases command wrote it.
  r=$work/next-old
  copy_fixture next-supabase "$r"
  {
    printf '# Notes\n\nA small notes app.\n\n'
    old_block 6
    cat "$LEGACY/issues.md"
  } >"$r/AGENTS.md"
  cp "$LEGACY/pointer-fd04f50.md" "$r/CLAUDE.md"
  mkdir -p "$r/.github/workflows"
  cat >"$r/release-please-config.json" <<'EOF'
{
  "$schema": "https://raw.githubusercontent.com/googleapis/release-please/main/schemas/config.json",
  "packages": {
    ".": {
      "release-type": "node",
      "changelog-path": "CHANGELOG.md",
      "include-v-in-tag": true
    }
  },
  "bump-minor-pre-major": true,
  "bump-patch-for-minor-pre-major": true
}
EOF
  printf '{\n  ".": "0.1.0"\n}\n' >"$r/.release-please-manifest.json"
  cat >"$r/.github/workflows/release-please.yml" <<'EOF'
name: release-please

on:
  push:
    branches:
      - main

permissions:
  contents: write
  pull-requests: write
  issues: write

jobs:
  release-please:
    runs-on: ubuntu-latest
    steps:
      - uses: googleapis/release-please-action@v4
        with:
          token: ${{ secrets.GITHUB_TOKEN }}
          config-file: release-please-config.json
          manifest-file: .release-please-manifest.json
EOF
  start_repo "$r"
  detected=$(sh "$SETUP/detect.sh" "$r")
  assert_exit 0 test "$(printf '%s\n' "$detected" | jq -c .stackHints)" = '["node-tooling","nextjs","supabase"]'
  assert_exit 0 test "$(printf '%s\n' "$detected" | jq -c '[.claude, .legacyBlocks]')" = '["pointer",["web-6","issues"]]'
  assert_exit 0 test "$(sh "$SETUP/project-file.sh" existing-ci "$r")" = .github/workflows/release-please.yml
  (cd "$r" && npm ci --no-progress >"$work/npm.out" 2>&1) || _assert_fail "npm ci failed:
$(cat "$work/npm.out")"
  for f in release-please-config.json .release-please-manifest.json .github/workflows/release-please.yml; do
    cp "$r/$f" "$work/$(basename "$f").before"
  done
  applied=$(apply "$r" "$answers")
  check_setup "$r"
  assert_contains "$(cat "$r/AGENTS.md")" 'A small notes app.'
  assert_contains "$(cat "$r/package.json")" 'git config core.hooksPath .githooks'
  for f in release-please-config.json .release-please-manifest.json .github/workflows/release-please.yml; do
    assert_file_same "$r/$f" "$work/$(basename "$f").before"
  done
  assert_contains "$(cat "$r/.githooks/dev-workflow.env")" .github/workflows/release-please.yml
  commits "$r" lib/bad.js "$bad_js"
  rerun "$r" "$answers"
  push "$r" 'All matched files use Prettier code style!' lib/notes.js 's/"Untitled"/"Unnamed"/'
  edits "$r" "$answers"

  # A fresh clone: npm ci turns the hooks on, through the prepare script setup added.
  git clone -q --branch feat/1-setup "$r.remote.git" "$work/next-clone" || _assert_fail "cannot clone"
  assert_exit 1 git -C "$work/next-clone" config core.hooksPath
  (cd "$work/next-clone" && npm ci --no-progress >"$work/npm.out" 2>&1) || _assert_fail "npm ci in a clone failed:
$(cat "$work/npm.out")"
  assert_exit 0 test "$(git -C "$work/next-clone" config core.hooksPath)" = .githooks

  # The whole verify, with the real row-level security test, against the app's own stack.
  no_docker "$r"
  (cd "$r" && npm run verify >"$work/verify.out" 2>&1) || _assert_fail "npm run verify failed:
$(cat "$work/verify.out")"
  no_leftovers "next-supabase's database test"
  assert_contains "$(cat "$work/verify.out")" 'notes_rls.test.sql .. ok'
  assert_contains "$(cat "$work/verify.out")" 'Result: PASS'
  echo "fixtures: next-supabase, old setup: ok, with the row-level security test"

  # An existing repo with no prior setup. Packages come from the first copy.
  r=$work/next-plain
  copy_fixture next-supabase "$r"
  start_repo "$r"
  cp -R "$work/next-old/node_modules" "$r/node_modules"
  applied=$(apply "$r" "$answers")
  for p in CLAUDE.md AGENTS.md#project AGENTS.md#workflow .claude/dev-workflow.json .githooks/pre-push; do
    assert_exit 0 test "$(printf '%s\n' "$applied" | jq -r --arg p "$p" 'select(.path == $p) | .action')" = create
  done
  check_setup "$r"
  commits "$r" lib/bad.js "$bad_js"
  rerun "$r" "$answers"
  push "$r" 'All matched files use Prettier code style!' lib/notes.js 's/"Untitled"/"Unnamed"/'
  edits "$r" "$answers"
  echo "fixtures: next-supabase, no prior setup: ok"
}

# --- uv, Litestar and Postgres in Docker: no Node, no stack file

litestar_postgres() {
  answers=$FIXTURES/litestar-postgres.answers.json
  bad_py="x = {'a':1}"
  breaks='s/return notes.all()/return notes.all()[1:]/'

  # An empty repo, set up before there's anything in it. The app comes afterwards.
  r=$work/litestar-empty
  new_repo "$r"
  assert_exit 0 test "$(sh "$SETUP/detect.sh" "$r" | jq -r .repo)" = empty
  apply "$r" "$answers" >/dev/null
  check_setup "$r"
  copy_fixture litestar-postgres "$r"
  detected=$(sh "$SETUP/detect.sh" "$r")
  assert_exit 0 test "$(printf '%s\n' "$detected" | jq -c '[.stackHints, .languages]')" = '[[],["python"]]'
  assert_exit 1 test -e "$r/package.json"
  (cd "$r" && uv sync --frozen >"$work/uv.out" 2>&1) || _assert_fail "uv sync failed:
$(cat "$work/uv.out")"
  commits "$r" app/bad.py "$bad_py"
  rerun "$r" "$answers"
  push "$r" 'All checks passed!' app/main.py "$breaks"
  edits "$r" "$answers"

  # The whole verify, with the real data-access test against the app's own Postgres.
  no_docker "$r"
  (cd "$r" && sh scripts/verify >"$work/verify.out" 2>&1) || _assert_fail "scripts/verify failed:
$(cat "$work/verify.out")"
  no_leftovers "litestar-postgres's database test"
  assert_contains "$(cat "$work/verify.out")" '2 passed'
  assert_contains "$(cat "$work/verify.out")" 'db-test: removing container dwtest-litestar-postgres-'
  echo "fixtures: litestar-postgres, empty repo: ok, with the data-access test"

  # An old block in CLAUDE.md at the older plugin version, under the project's own text.
  r=$work/litestar-old
  copy_fixture litestar-postgres "$r"
  {
    printf '# Notes service\n\nA small notes API.\n\n'
    old_block 5
  } >"$r/CLAUDE.md"
  start_repo "$r"
  assert_exit 0 test "$(sh "$SETUP/detect.sh" "$r" | jq -c '[.agents, .claude, .legacyBlocks]')" = '[false,"content",["web-5"]]'
  (cd "$r" && uv sync --frozen >"$work/uv.out" 2>&1) || _assert_fail "uv sync failed:
$(cat "$work/uv.out")"
  apply "$r" "$answers" >/dev/null
  check_setup "$r"
  assert_contains "$(cat "$r/AGENTS.md")" 'A small notes API.'
  commits "$r" app/bad.py "$bad_py"
  rerun "$r" "$answers"
  push "$r" 'All checks passed!' app/main.py "$breaks"
  edits "$r" "$answers"
  echo "fixtures: litestar-postgres, old block in CLAUDE.md: ok"

  # An existing repo with no prior setup.
  r=$work/litestar-plain
  copy_fixture litestar-postgres "$r"
  start_repo "$r"
  (cd "$r" && uv sync --frozen >"$work/uv.out" 2>&1) || _assert_fail "uv sync failed:
$(cat "$work/uv.out")"
  applied=$(apply "$r" "$answers")
  for p in CLAUDE.md AGENTS.md#project AGENTS.md#workflow .claude/dev-workflow.json .githooks/pre-push; do
    assert_exit 0 test "$(printf '%s\n' "$applied" | jq -r --arg p "$p" 'select(.path == $p) | .action')" = create
  done
  check_setup "$r"
  assert_exit 0 test "$(jq -c .stack "$r/.claude/dev-workflow.json")" = '[]'
  commits "$r" app/bad.py "$bad_py"
  rerun "$r" "$answers"
  push "$r" 'All checks passed!' app/main.py "$breaks"
  edits "$r" "$answers"
  echo "fixtures: litestar-postgres, no prior setup: ok"
}

# --- run them

selected=${DW_FIXTURES:-next-supabase litestar-postgres}
for name in $selected; do
  case $name in
    next-supabase) next_supabase ;;
    litestar-postgres) litestar_postgres ;;
    *) _assert_fail "fixtures: no fixture called $name" ;;
  esac
done
no_leftovers fixtures
echo "fixtures: $selected passed"
