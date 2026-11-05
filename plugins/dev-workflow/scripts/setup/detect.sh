#!/bin/sh
# Usage: detect.sh <path>
#
# Prints, as JSON, what setup needs to know about the repo holding <path>: whether
# it's empty, its git remote and default branch, stack and language markers, any
# existing hook tool, the state of AGENTS.md and CLAUDE.md, the old rule blocks in
# them, and whether it has a project file. A path inside a repo means the whole repo.
# Changes nothing. Exits 2 on bad usage or a missing tool.
#
# The fields:
#   repo          "empty" (no commits and no files) or "existing"
#   git           whether the path is in a git work tree
#   remote        "github" if origin's host is github.com, "other", or "none"
#   defaultBranch origin/HEAD's branch, else the current branch if there is no
#                 remote, else "main"
#   stackHints    stack files that apply: node-tooling, nextjs, astro, supabase
#   languages     other languages found: python, rust, go and so on
#   hookTool      "husky", "lefthook", "pre-commit", "simple-git-hooks" or "none"
#   hooksPath     the repo's own core.hooksPath, or null
#   agents        whether AGENTS.md exists
#   claude        CLAUDE.md is "absent", a "symlink", the "import" @AGENTS.md, an
#                 old "pointer", or "content"
#   legacyBlocks  old blocks in either file: web-5, web-6, issues
#   projectFile   whether .claude/dev-workflow.json exists

die() {
  printf 'detect.sh: %s\n' "$*" >&2
  exit 2
}

missing=
for tool in git jq; do
  command -v "$tool" >/dev/null 2>&1 || missing="$missing $tool"
done
[ -z "$missing" ] || die "missing required tools:$missing"
[ "$#" -eq 1 ] || die "usage: detect.sh <path>"
[ -d "$1" ] || die "not a folder: $1"

# Git hooks export these, and they would point git at another repo.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE

# shellcheck source=plugins/dev-workflow/scripts/setup/legacy.sh
. "$(dirname -- "$0")/legacy.sh"
[ -f "$LEGACY_DIR/issues.md" ] || die "published texts not found in: $LEGACY_DIR"

if root=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null) && [ -n "$root" ]; then
  git=true
else
  git=false
  root=$(CDPATH='' cd -- "$1" && pwd) || die "cannot enter: $1"
fi

exists() { # <path>...: 0 if any exists, even as a broken symlink
  for _path in "$@"; do
    if [ -e "$_path" ] || [ -L "$_path" ]; then return 0; fi
  done
  return 1
}

# --- repo

repo=empty
if [ "$git" = true ] && git -C "$root" rev-parse --verify -q 'HEAD^{commit}' >/dev/null; then
  repo=existing
else
  for entry in "$root"/* "$root"/.[!.]* "$root"/..?*; do
    exists "$entry" || continue
    case ${entry##*/} in
      .git | .DS_Store) ;;
      *) repo=existing ;;
    esac
  done
fi

# --- remote and default branch

# remote_kind <url>: github only when the host really is github.com.
remote_kind() {
  _url=$(printf '%s' "$1" | LC_ALL=C tr '[:upper:]' '[:lower:]')
  case $_url in
    *://*)
      case ${_url%%://*} in
        http | https | ssh | git | git+ssh | ssh+git) ;;
        *) echo other && return ;;
      esac
      _host=${_url#*://}
      _host=${_host%%[/?#\\]*}
      _host=${_host##*@}
      _host=${_host%%:*}
      ;;
    *:*)
      # The scp form, host:path. A slash before the colon makes it a local path.
      _host=${_url%%:*}
      case $_host in */*) echo other && return ;; esac
      _host=${_host##*@}
      ;;
    *) echo other && return ;;
  esac
  if [ "$_host" = github.com ]; then echo github; else echo other; fi
}

remote=none
default_branch=main
hooks_path=
if [ "$git" = true ]; then
  if url=$(git -C "$root" remote get-url origin 2>/dev/null); then
    remote=$(remote_kind "$url")
  elif [ -n "$(git -C "$root" remote 2>/dev/null)" ]; then
    remote=other
  fi

  if ref=$(git -C "$root" symbolic-ref -q refs/remotes/origin/HEAD 2>/dev/null); then
    default_branch=${ref#refs/remotes/origin/}
  elif [ "$remote" = none ] && ref=$(git -C "$root" symbolic-ref -q HEAD 2>/dev/null); then
    default_branch=${ref#refs/heads/}
  fi

  hooks_path=$(git -C "$root" config --local --get core.hooksPath 2>/dev/null)
fi

# --- stack hints and languages, at the root and one folder down

node=false nextjs=false astro=false supabase=false
languages=
for dir in "$root" "$root"/*/; do
  dir=${dir%/}
  [ -d "$dir" ] || continue
  case ${dir##*/} in
    node_modules | vendor | venv | dist | build | target) [ "$dir" = "$root" ] || continue ;;
  esac

  if [ -f "$dir/package.json" ]; then
    node=true
    deps=$(jq -r '
      objects | [.dependencies, .devDependencies, .peerDependencies, .optionalDependencies]
      | map(objects | keys[]) | .[]
    ' "$dir/package.json" 2>/dev/null)
    while IFS= read -r dep; do
      case $dep in
        next) nextjs=true ;;
        astro) astro=true ;;
        supabase | @supabase/*) supabase=true ;;
      esac
    done <<DEPS
$deps
DEPS
  fi
  if exists "$dir"/next.config.*; then nextjs=true; fi
  if exists "$dir"/astro.config.*; then astro=true; fi
  if exists "$dir/supabase/config.toml"; then supabase=true; fi

  if exists "$dir/pyproject.toml" "$dir/requirements.txt" "$dir/setup.py" "$dir/Pipfile"; then languages="$languages python"; fi
  if exists "$dir/Cargo.toml"; then languages="$languages rust"; fi
  if exists "$dir/go.mod"; then languages="$languages go"; fi
  if exists "$dir/Gemfile"; then languages="$languages ruby"; fi
  if exists "$dir/pom.xml" "$dir/build.gradle" "$dir/build.gradle.kts"; then languages="$languages java"; fi
  if exists "$dir/composer.json"; then languages="$languages php"; fi
  if exists "$dir/mix.exs"; then languages="$languages elixir"; fi
  if exists "$dir/Package.swift"; then languages="$languages swift"; fi
  if exists "$dir/pubspec.yaml"; then languages="$languages dart"; fi
  if exists "$dir"/*.csproj "$dir"/*.fsproj "$dir"/*.sln; then languages="$languages dotnet"; fi
done

stack_hints=
[ "$node" = false ] || stack_hints="$stack_hints node-tooling"
[ "$nextjs" = false ] || stack_hints="$stack_hints nextjs"
[ "$astro" = false ] || stack_hints="$stack_hints astro"
[ "$supabase" = false ] || stack_hints="$stack_hints supabase"

# --- hook tool, at the root only

hook_tool=none
lefthook_configs=
for name in lefthook .lefthook .config/lefthook; do
  for ext in yml yaml toml json jsonc; do
    lefthook_configs="$lefthook_configs $name.$ext"
  done
done
# shellcheck disable=SC2086 # Plain names, split on purpose.
set -- $lefthook_configs
if [ -d "$root/.husky" ]; then
  hook_tool=husky
elif (cd "$root" && exists "$@"); then
  hook_tool=lefthook
elif exists "$root/.pre-commit-config.yaml"; then
  hook_tool=pre-commit
elif [ -f "$root/package.json" ] && jq -e '
  objects | has("simple-git-hooks")
    or ([.dependencies, .devDependencies] | map(objects | has("simple-git-hooks")) | any)
' "$root/package.json" >/dev/null 2>&1; then
  hook_tool=simple-git-hooks
fi

# --- AGENTS.md, CLAUDE.md and the old blocks in them

agents=false
if exists "$root/AGENTS.md"; then agents=true; fi

claude_file=$root/CLAUDE.md
claude=$(legacy_claude_state "$claude_file")

blocks=
# A symlink isn't read: it could lead to a private file outside the repo.
for file in "$root/AGENTS.md" "$claude_file"; do
  if [ ! -L "$file" ] && [ -f "$file" ] && [ -r "$file" ]; then
    blocks="$blocks
$(legacy_blocks_in "$file")"
  fi
done

# --- the JSON

list() { # <words or lines>: a JSON array of the non-empty ones
  printf '%s\n' "$1" | tr ' ' '\n' | jq -Rnc '[inputs | select(length > 0)]'
}

projectFile=false
if exists "$root/.claude/dev-workflow.json"; then projectFile=true; fi

jq -n \
  --arg repo "$repo" \
  --argjson git "$git" \
  --arg remote "$remote" \
  --arg defaultBranch "$default_branch" \
  --argjson stackHints "$(list "$stack_hints")" \
  --argjson languages "$(list "$languages" | jq -c 'unique')" \
  --arg hookTool "$hook_tool" \
  --arg hooksPath "$hooks_path" \
  --argjson agents "$agents" \
  --arg claude "$claude" \
  --argjson found "$(list "$blocks")" \
  --argjson projectFile "$projectFile" \
  '{
    repo: $repo,
    git: $git,
    remote: $remote,
    defaultBranch: $defaultBranch,
    stackHints: $stackHints,
    languages: $languages,
    hookTool: $hookTool,
    hooksPath: (if $hooksPath == "" then null else $hooksPath end),
    agents: $agents,
    claude: $claude,
    legacyBlocks: (["web-5", "web-6", "issues"] | map(select(. as $id | $found | index($id)))),
    projectFile: $projectFile
  }'
