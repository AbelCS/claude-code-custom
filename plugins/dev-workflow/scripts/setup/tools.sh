#!/bin/sh
# Usage: tools.sh [<root>]
#
# Says which of the tools setup relies on are there, as one JSON object:
#   { "required": [...], "plugins": [...], "other": [...] }
# Each entry is { "name": str, "present": bool, "install": str, "detail": str? }, where
# install is the exact command that installs it, or fixes what's wrong.
#   required  git, gh signed in, jq, and Claude Code MIN_CLAUDE or later. Setup stops if
#             any of them isn't present.
#   plugins   the list in ../lib/plugins.txt, which the session-start hook checks too, as
#             installed_plugins.json has them for <root>. Each also has "id", "when"
#             (always, or screens), and "marketplace" when it isn't the official one.
#             superpowers also has "missingSkills": the skills the methodology names
#             that its installed copy doesn't have, since no version can be pinned.
#   other     codex, the Codex CLI, and a browser: playwright on the PATH or in
#             <root>'s node_modules, or a browser plugin. Missing means the step that
#             needs one warns.
#
# <root> is the project, by default the current folder: a plugin installed for one
# project counts only there. Works without jq, saying so, as jq is one of the tools.
# Changes nothing, and exits 0 whatever is missing; 2 on bad usage.
#
# $DW_GH and $DW_CLAUDE name gh and claude, for tests. installed_plugins.json is in
# $CLAUDE_CONFIG_DIR/plugins, else ~/.claude/plugins.

MIN_CLAUDE=2.1.295
SUPERPOWERS_SKILLS="brainstorming writing-plans test-driven-development systematic-debugging verification-before-completion receiving-code-review finishing-a-development-branch"
BROWSER_PLUGINS="playwright chrome-devtools-mcp browser-use"

[ "$#" -le 1 ] || {
  echo "usage: tools.sh [<root>]" >&2
  exit 2
}
root=${1:-$PWD}
[ -d "$root" ] || {
  printf 'tools.sh: not a folder: %s\n' "$root" >&2
  exit 2
}
GH=${DW_GH:-gh}
CLAUDE=${DW_CLAUDE:-claude}

case $0 in
  */*) here=${0%/*} ;;
  *) here=. ;;
esac
lib=$here/../lib
# shellcheck source=plugins/dev-workflow/scripts/lib/common.sh
. "$lib/common.sh"
# shellcheck source=plugins/dev-workflow/scripts/lib/version.sh
. "$lib/version.sh"
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE

have() { command -v "$1" >/dev/null 2>&1; }

# str <text>: a JSON string.
str() {
  _dw_json_escape "$1"
  printf '"%s"' "$_dw_escaped"
}

# entry <name> <present> <install> [detail] [more JSON fields]
entry() {
  printf '{"name":%s,"present":%s,"install":%s' "$(str "$1")" "$2" "$(str "$3")"
  [ -z "${4:-}" ] || printf ',"detail":%s' "$(str "$4")"
  [ -z "${5:-}" ] || printf ',%s' "$5"
  printf '}'
}

# list <entries...>: a JSON array of them.
list() {
  printf '['
  _sep=
  for _e in "$@"; do
    printf '%s%s' "$_sep" "$_e"
    _sep=,
  done
  printf ']'
}

# --- required

if have git; then git_present=true; else git_present=false; fi
git_entry=$(entry git "$git_present" "brew install git, or apt-get install git")

if ! have "$GH"; then
  gh_entry=$(entry gh false "brew install gh, or see https://cli.github.com, then gh auth login")
elif "$GH" auth status >/dev/null 2>&1; then
  gh_entry=$(entry gh true "gh auth login")
else
  gh_entry=$(entry gh false "gh auth login" "installed, but not signed in to GitHub")
fi

if have jq; then jq_present=true; else jq_present=false; fi
jq_entry=$(entry jq "$jq_present" "brew install jq, or apt-get install jq")

claude_install="curl -fsSL https://claude.ai/install.sh | bash"
if ! have "$CLAUDE"; then
  claude_entry=$(entry claude false "$claude_install" "Claude Code $MIN_CLAUDE or later is needed")
else
  claude_version=$("$CLAUDE" --version 2>/dev/null)
  claude_version=${claude_version%% *}
  read_version "$MIN_CLAUDE"
  min_parts=$version_parts
  if ! read_version "$claude_version"; then
    claude_entry=$(entry claude false "claude update" "couldn't read its version, and $MIN_CLAUDE or later is needed")
  elif version_is_older "$version_parts" "$min_parts"; then
    claude_entry=$(entry claude false "claude update" "version $claude_version, and $MIN_CLAUDE or later is needed")
  else
    claude_entry=$(entry claude true "claude update" "version $claude_version")
  fi
fi

# --- plugins

registry=${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/installed_plugins.json
registry_problem=
installed=
if ! have jq; then
  registry_problem="jq is missing, so the plugins weren't checked"
elif [ -e "$registry" ]; then
  main=
  if have git && common=$(git -C "$root" rev-parse --path-format=absolute --git-common-dir 2>/dev/null); then
    main=${common%/.git}
  fi
  here_dir=$(cd "$root" && pwd)
  # One line each: name, then the install path.
  if ! installed=$(jq -re -L "$lib" --arg here "$here_dir" --arg main "$main" \
    'include "installed-plugins"; installed_for($here; $main) | map("\(.name)\t\(.installPath)") | join("\n")' \
    "$registry" 2>/dev/null); then
    registry_problem="couldn't read installed_plugins.json, so the plugins weren't checked"
    installed=
  fi
fi

# install_path <name>: sets path to where it's installed; returns 1 if it isn't.
install_path() {
  while IFS="$_dw_tab" read -r _name _path; do
    if [ "$_name" = "$1" ]; then
      path=$_path
      return 0
    fi
  done <<EOF
$installed
EOF
  return 1
}

set --
while read -r p_name p_when p_marketplace p_id; do
  case $p_name in '' | '#'*) continue ;; esac
  install="claude plugin install $p_id"
  more="\"id\":$(str "$p_id"),\"when\":$(str "$p_when")"
  if [ "$p_marketplace" != - ]; then
    install="claude plugin marketplace add $p_marketplace && $install"
    more="$more,\"marketplace\":$(str "$p_marketplace")"
  fi
  if [ -n "$registry_problem" ]; then
    set -- "$@" "$(entry "$p_name" false "$install" "$registry_problem" "$more")"
    continue
  fi
  if ! install_path "$p_name"; then
    set -- "$@" "$(entry "$p_name" false "$install" "" "$more")"
    continue
  fi
  detail=
  if [ "$p_name" = superpowers ]; then
    missing=
    missing_json=
    for skill in $SUPERPOWERS_SKILLS; do
      [ ! -f "$path/skills/$skill/SKILL.md" ] || continue
      missing="$missing $skill"
      missing_json="$missing_json${missing_json:+,}$(str "$skill")"
    done
    more="$more,\"missingSkills\":[$missing_json]"
    [ -z "$missing" ] || detail="installed, but without the skills the methodology names:$missing"
  fi
  set -- "$@" "$(entry "$p_name" true "$install" "$detail" "$more")"
done <"$lib/plugins.txt"
plugins=$(list "$@")

# --- other

if have codex; then codex_present=true; else codex_present=false; fi
codex_entry=$(entry codex "$codex_present" "npm install -g @openai/codex" "" '"for":"independent-review"')

browser_present=false
browser_detail=
if have playwright || [ -x "$root/node_modules/.bin/playwright" ]; then
  browser_present=true
  browser_detail=playwright
else
  for b in $BROWSER_PLUGINS; do
    if [ -z "$registry_problem" ] && install_path "$b"; then
      browser_present=true
      browser_detail="the $b plugin"
      break
    fi
  done
fi
browser_entry=$(entry browser "$browser_present" "claude plugin install playwright@claude-plugins-official" "$browser_detail" '"for":"screen-check"')

printf '{"required":%s,"plugins":%s,"other":%s}\n' \
  "$(list "$git_entry" "$gh_entry" "$jq_entry" "$claude_entry")" "$plugins" \
  "$(list "$codex_entry" "$browser_entry")"
