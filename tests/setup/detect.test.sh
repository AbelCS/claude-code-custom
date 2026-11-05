#!/bin/sh
# detect.sh <path>: what setup finds in a folder, as JSON. One case per value of
# each field, in temp repos.

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
# shellcheck source=tests/lib/assert.sh
. "$ROOT/tests/lib/assert.sh"

DETECT="$ROOT/plugins/dev-workflow/scripts/setup/detect.sh"
LEGACY="$ROOT/plugins/dev-workflow/skills/setup/references/legacy"

# A global core.hooksPath or init.defaultBranch on this machine must not leak in.
GIT_CONFIG_GLOBAL=$(tmp_dir)/gitconfig
: >"$GIT_CONFIG_GLOBAL"
export GIT_CONFIG_GLOBAL

detect() { # <path>: prints the JSON, failing unless it exits 0 with valid JSON
  _json=$(sh "$DETECT" "$1" 2>&1) || _assert_fail "detect.sh failed on $1:
$_json"
  printf '%s\n' "$_json" | jq -e 'type == "object"' >/dev/null ||
    _assert_fail "not a JSON object for $1:
$_json"
  printf '%s\n' "$_json"
}

field() { # <path> <jq filter>: the filter's compact output
  detect "$1" | jq -c "$2"
}

assert_field() { # <path> <jq filter> <expected compact JSON>
  _actual=$(field "$1" "$2")
  [ "$_actual" = "$3" ] || _assert_fail "$2 for $1: expected $3, got $_actual"
}

commit() { # <repo>
  git -C "$1" commit -q --allow-empty -m "chore: start" || _assert_fail "could not commit in $1"
}

block() { # <version>: a whole published web block
  first=1
  for part in "$LEGACY/web-$1".*.md; do
    [ "$first" -eq 1 ] || printf '\n'
    first=0
    cat "$part"
  done
}

# --- the whole shape, for an existing repo

r=$(tmp_dir)/repo
new_repo "$r"
commit "$r"
assert_field "$r" 'keys' '["agents","claude","defaultBranch","git","gitHooks","hookTool","hooksPath","hooksPathScope","languages","legacyBlocks","projectFile","remote","repo","stackHints"]'
assert_field "$r" '[.repo, .git, .remote, .defaultBranch, .hookTool, .hooksPath, .hooksPathScope, .gitHooks, .agents, .claude, .projectFile]' '["existing",true,"none","main","none",null,null,[],false,"absent",false]'
assert_field "$r" '[.stackHints, .languages, .legacyBlocks]' '[[],[],[]]'

# --- repo and git

r=$(tmp_dir)/empty-git
mkdir "$r"
git -C "$r" init -q -b trunk
assert_field "$r" '[.repo, .git]' '["empty",true]'
touch "$r/.DS_Store"
assert_field "$r" '.repo' '"empty"'
touch "$r/README.md"
assert_field "$r" '.repo' '"existing"'

r=$(tmp_dir)
assert_field "$r" '[.repo, .git, .remote, .defaultBranch, .hooksPath, .hooksPathScope, .gitHooks]' '["empty",false,"none","main",null,null,[]]'
touch "$r/notes.txt"
assert_field "$r" '[.repo, .git]' '["existing",false]'

# --- remote

r=$(tmp_dir)/remote
new_repo "$r"
commit "$r"
git -C "$r" remote add origin https://github.com/o/r.git
for url in \
  https://github.com/o/r.git \
  http://github.com/o/r \
  https://user:token@github.com/o/r.git \
  https://github.com:443/o/r \
  HTTPS://GitHub.COM/o/r \
  ssh://git@github.com/o/r.git \
  ssh://git@github.com:22/o/r.git \
  git+ssh://git@github.com/o/r.git \
  git://github.com/o/r.git \
  git@github.com:o/r.git \
  github.com:o/r.git; do
  git -C "$r" remote set-url origin "$url"
  assert_field "$r" '.remote' '"github"'
done
for url in \
  https://github.com.evil.example/o/r \
  https://evil.example/github.com/o/r \
  https://github.com@evil.example/o/r \
  https://user:github.com@evil.example/o/r \
  'https://evil.example?h=github.com' \
  'https://evil.example#@github.com/o/r' \
  https://notgithub.com/o/r \
  https://www.github.com.example/o/r \
  git@evil.example:github.com/o/r \
  git@github.com.evil.example:o/r \
  ssh://github.com@evil.example/o/r \
  file:///tmp/github.com/r.git \
  /tmp/github.com/r.git \
  ./github.com:o/r \
  'hg::https://github.com/o/r'; do
  git -C "$r" remote set-url origin "$url"
  assert_field "$r" '.remote' '"other"'
done
# The URL git really uses, after insteadOf.
git -C "$r" config url.https://github.com/.insteadOf gh:
git -C "$r" remote set-url origin gh:o/r
assert_field "$r" '.remote' '"github"'
# Only origin counts.
git -C "$r" remote rename origin upstream
git -C "$r" remote set-url upstream https://github.com/o/r.git
assert_field "$r" '.remote' '"other"'

# --- defaultBranch

r=$(tmp_dir)/branches
new_repo "$r"
commit "$r"
git -C "$r" branch -q trunk
git -C "$r" branch -q release/1.x
git -C "$r" checkout -q -b feature/x
# No remote: the current branch, whatever init.defaultBranch says.
assert_field "$r" '.defaultBranch' '"feature/x"'
git -C "$r" -c init.defaultBranch=other checkout -q --detach
assert_field "$r" '.defaultBranch' '"main"'
git -C "$r" checkout -q feature/x
# A remote without origin/HEAD: main.
git -C "$r" remote add origin https://github.com/o/r.git
assert_field "$r" '.defaultBranch' '"main"'
git -C "$r" update-ref refs/remotes/origin/trunk HEAD
git -C "$r" update-ref refs/remotes/origin/release/1.x HEAD
git -C "$r" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/trunk
assert_field "$r" '.defaultBranch' '"trunk"'
git -C "$r" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/release/1.x
assert_field "$r" '.defaultBranch' '"release/1.x"'
# A local branch named like the remote one doesn't confuse it.
git -C "$r" branch -q origin/release/1.x
assert_field "$r" '.defaultBranch' '"release/1.x"'

# An empty repo: its unborn branch.
r=$(tmp_dir)/unborn
mkdir "$r"
git -C "$r" -c init.defaultBranch=other init -q -b trunk
assert_field "$r" '.defaultBranch' '"trunk"'

# --- stackHints and languages

r=$(tmp_dir)/stack
mkdir "$r"
assert_field "$r" '[.stackHints, .languages]' '[[],[]]'
printf '{"name":"x"}\n' >"$r/package.json"
assert_field "$r" '[.stackHints, .languages]' '[["node-tooling"],[]]'
printf '{"dependencies":{"next":"16.0.0","@supabase/supabase-js":"2.0.0"}}\n' >"$r/package.json"
assert_field "$r" '.stackHints' '["node-tooling","nextjs","supabase"]'
printf '{"devDependencies":{"astro":"5.0.0"}}\n' >"$r/package.json"
assert_field "$r" '.stackHints' '["node-tooling","astro"]'
# Invalid or odd JSON still means Node tooling, and nothing else.
printf '{ not json\n' >"$r/package.json"
assert_field "$r" '.stackHints' '["node-tooling"]'
printf '["next"]\n' >"$r/package.json"
assert_field "$r" '.stackHints' '["node-tooling"]'
printf '{"dependencies":"next"}\n' >"$r/package.json"
assert_field "$r" '.stackHints' '["node-tooling"]'
rm "$r/package.json"
# Config files count without a dependency.
touch "$r/next.config.mjs"
assert_field "$r" '.stackHints' '["nextjs"]'
rm "$r/next.config.mjs"
touch "$r/astro.config.ts"
assert_field "$r" '.stackHints' '["astro"]'
rm "$r/astro.config.ts"
mkdir "$r/supabase"
touch "$r/supabase/config.toml"
assert_field "$r" '.stackHints' '["supabase"]'
rm -r "$r/supabase"

# A non-Node repo: no stack hints, only languages.
r=$(tmp_dir)/python
mkdir "$r"
touch "$r/pyproject.toml"
assert_field "$r" '[.stackHints, .languages]' '[[],["python"]]'
# A mixed repo, with one level of subfolders.
mkdir "$r/ui" "$r/engine" "$r/svc"
printf '{"dependencies":{"next":"16.0.0"}}\n' >"$r/ui/package.json"
touch "$r/engine/Cargo.toml" "$r/svc/go.mod"
assert_field "$r" '[.stackHints, .languages]' '[["node-tooling","nextjs"],["go","python","rust"]]'
# Deeper, or in vendored and dependency folders, doesn't count.
r=$(tmp_dir)/deep
mkdir -p "$r/a/b" "$r/node_modules/x" "$r/vendor"
touch "$r/a/b/package.json" "$r/node_modules/package.json" "$r/vendor/go.mod"
assert_field "$r" '[.stackHints, .languages]' '[[],[]]'

# --- hookTool and hooksPath

r=$(tmp_dir)/hooks
new_repo "$r"
assert_field "$r" '.hookTool' '"none"'
printf '{"simple-git-hooks":{"pre-commit":"npm test"}}\n' >"$r/package.json"
assert_field "$r" '.hookTool' '"simple-git-hooks"'
printf '{"devDependencies":{"simple-git-hooks":"2.0.0"}}\n' >"$r/package.json"
assert_field "$r" '.hookTool' '"simple-git-hooks"'
touch "$r/.pre-commit-config.yaml"
assert_field "$r" '.hookTool' '"pre-commit"'
for name in lefthook.yml .lefthook.yml lefthook.yaml lefthook.toml .lefthook.json lefthook.jsonc .config/lefthook.yml; do
  mkdir -p "$r/.config"
  touch "$r/$name"
  assert_field "$r" '.hookTool' '"lefthook"'
  rm "$r/$name"
done
mkdir "$r/.husky"
assert_field "$r" '.hookTool' '"husky"'

git -C "$r" config core.hooksPath '.husky/_'
assert_field "$r" '[.hooksPath, .hooksPathScope]' '[".husky/_","local"]'
# The value git uses, from wherever it comes: a global one stops .git/hooks running too.
git -C "$r" config --unset core.hooksPath
git config --file "$GIT_CONFIG_GLOBAL" core.hooksPath /global/hooks
assert_field "$r" '[.hooksPath, .hooksPathScope]' '["/global/hooks","global"]'
# The repo's own wins over it, as in git.
git -C "$r" config core.hooksPath .githooks
assert_field "$r" '[.hooksPath, .hooksPathScope]' '[".githooks","local"]'
git -C "$r" config --unset core.hooksPath
: >"$GIT_CONFIG_GLOBAL"
assert_field "$r" '[.hooksPath, .hooksPathScope]' '[null,null]'
# One given on the command line, as GIT_CONFIG_PARAMETERS passes it, counts as well.
assert_exit 0 test "$(git -c core.hooksPath=/cmd/hooks -C "$r" config --show-scope --get core.hooksPath | cut -f 1)" = command
hp=$(GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=/env/hooks sh "$DETECT" "$r" | jq -c '[.hooksPath, .hooksPathScope]')
assert_exit 0 test "$hp" = '["/env/hooks","command"]'

# gitHooks: the hooks git runs from .git/hooks with no hooks path, by name. Git's own
# samples, and a file that isn't executable, which git skips, don't count.
hooks_dir=$(git -C "$r" rev-parse --absolute-git-dir)/hooks
mkdir -p "$hooks_dir"
printf '#!/bin/sh\n' >"$hooks_dir/pre-commit.sample"
printf '#!/bin/sh\n' >"$hooks_dir/post-merge"
printf '#!/bin/sh\n' >"$hooks_dir/pre-push"
printf '#!/bin/sh\n' >"$hooks_dir/commit-msg"
chmod +x "$hooks_dir/pre-commit.sample" "$hooks_dir/pre-push" "$hooks_dir/commit-msg"
mkdir "$hooks_dir/pre-rebase"
assert_field "$r" '.gitHooks' '["commit-msg","pre-push"]'
# A linked worktree shares them, as git runs the same ones there.
commit "$r"
wt=$(tmp_dir)/wt
git -C "$r" worktree add -q "$wt" 2>/dev/null || _assert_fail "cannot add a worktree"
assert_field "$wt" '.gitHooks' '["commit-msg","pre-push"]'
rm -f "$hooks_dir/pre-push" "$hooks_dir/commit-msg"
assert_field "$r" '.gitHooks' '[]'
# Detecting changes no git config.
before=$(git -C "$r" config --local --list)
detect "$r" >/dev/null
assert_exit 0 test "$(git -C "$r" config --local --list)" = "$before"

# --- agents, claude and legacyBlocks

r=$(tmp_dir)/files
new_repo "$r"
assert_field "$r" '[.agents, .claude, .legacyBlocks]' '[false,"absent",[]]'
printf '# Project\n' >"$r/AGENTS.md"
assert_field "$r" '.agents' 'true'

printf '@AGENTS.md\n' >"$r/CLAUDE.md"
assert_field "$r" '.claude' '"import"'
printf '@AGENTS.md\r\n' >"$r/CLAUDE.md"
assert_field "$r" '.claude' '"import"'
printf '@AGENTS.md' >"$r/CLAUDE.md"
assert_field "$r" '.claude' '"import"'
for pointer in "$LEGACY"/pointer-*.md; do
  cp "$pointer" "$r/CLAUDE.md"
  assert_field "$r" '.claude' '"pointer"'
  sed 's/$/\r/' "$pointer" >"$r/CLAUDE.md"
  assert_field "$r" '.claude' '"pointer"'
  { cat "$pointer"; printf '\nMore.\n'; } >"$r/CLAUDE.md"
  assert_field "$r" '.claude' '"content"'
done
printf '@AGENTS.md\n\nMore.\n' >"$r/CLAUDE.md"
assert_field "$r" '.claude' '"content"'
: >"$r/CLAUDE.md"
assert_field "$r" '.claude' '"content"'

# The old setup wrote its block straight into CLAUDE.md.
block 5 >"$r/CLAUDE.md"
assert_field "$r" '[.claude, .legacyBlocks]' '["content",["web-5"]]'
# Blocks in either file count, in a fixed order.
cp "$LEGACY/issues.md" "$r/CLAUDE.md"
{ printf '# Project\n\n'; block 6; } >"$r/AGENTS.md"
assert_field "$r" '[.claude, .legacyBlocks]' '["content",["web-6","issues"]]'
block 5 >"$r/CLAUDE.md"
assert_field "$r" '.legacyBlocks' '["web-5","web-6"]'

# A symlink is a symlink, whatever it points to.
rm "$r/CLAUDE.md"
ln -s AGENTS.md "$r/CLAUDE.md"
assert_field "$r" '[.claude, .legacyBlocks]' '["symlink",["web-6"]]'
rm "$r/CLAUDE.md"
printf '@AGENTS.md\n' >"$r/import"
ln -s import "$r/CLAUDE.md"
assert_field "$r" '.claude' '"symlink"'
rm "$r/CLAUDE.md"
ln -s missing "$r/CLAUDE.md"
assert_field "$r" '.claude' '"symlink"'

# --- projectFile

r=$(tmp_dir)/project
new_repo "$r"
assert_field "$r" '.projectFile' 'false'
mkdir "$r/.claude"
printf '{}\n' >"$r/.claude/dev-workflow.json"
assert_field "$r" '.projectFile' 'true'

# --- paths: spaces, subfolders, and a GIT_DIR pointing elsewhere

r="$(tmp_dir)/a repo with spaces"
new_repo "$r"
commit "$r"
mkdir -p "$r/sub folder/deeper" "$r/.claude"
printf '{}\n' >"$r/.claude/dev-workflow.json"
printf '{}\n' >"$r/package.json"
printf '@AGENTS.md\n' >"$r/CLAUDE.md"
assert_field "$r/sub folder/deeper" '[.git, .projectFile, .claude, .stackHints]' '[true,true,"import",["node-tooling"]]'
(cd "$r/sub folder" && sh "$DETECT" .) >"$(tmp_dir)/out" || _assert_fail "detect.sh failed on a relative path"
other=$(tmp_dir)/other
new_repo "$other"
assert_field "$r" '.projectFile' 'true'
(
  GIT_DIR="$other/.git"
  export GIT_DIR
  assert_field "$r" '[.git, .projectFile]' '[true,true]'
) || exit 1

# --- values that need escaping stay valid JSON

r=$(tmp_dir)/odd
new_repo "$r"
commit "$r"
git -C "$r" checkout -q -b 'we"ird'
git -C "$r" config core.hooksPath 'a "quoted"
path'
assert_field "$r" '.defaultBranch' '"we\"ird"'
assert_field "$r" '.hooksPath' '"a \"quoted\"\npath"'

# --- errors

assert_exit 2 sh "$DETECT"
assert_exit 2 sh "$DETECT" "$(tmp_dir)/missing"
touch "$r/file"
assert_exit 2 sh "$DETECT" "$r/file"
# Without jq it says so, rather than printing something that isn't JSON.
assert_exit 2 env PATH=/nonexistent /bin/sh "$DETECT" "$r"
assert_contains "$_assert_output" "jq"

# --- a CLAUDE.md link isn't read for old blocks, wherever it points

r=$(tmp_dir)/claude-link
new_repo "$r"
away=$(tmp_dir)
block 5 >"$away/rules.md"
ln -s "$away/rules.md" "$r/CLAUDE.md"
assert_field "$r" '[.claude, .legacyBlocks]' '["symlink",[]]'
