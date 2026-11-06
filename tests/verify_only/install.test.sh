#!/bin/sh
# Installs the plugin the way users get it, from this marketplace served as a git
# repository, each case in its own CLAUDE_CONFIG_DIR in a temp folder, never the real
# ~/.claude. It checks a fresh install, the move from web-dev-workflow and from
# dev-workflow 0.2.0, the components a session sees, the rewrite of a project's
# enabledPlugins key, and what `${user_config.*}` becomes in a skill.
#
# The marketplace is a bare repo in the temp folder. A git config that exists only for
# this test points its https URL there, so Claude Code clones and caches it as it would
# from GitHub. "Old" is the last commit that still had web-dev-workflow; "new" is this
# checkout, uncommitted files included.
#
# Sessions run with no login, since the config folder is new, so they stop before any
# model call and cost nothing. Each is still capped, in case a login reaches them.
# docs/hook-behaviour.md records what this test saw.

for needed in claude git jq; do
  if ! command -v "$needed" >/dev/null 2>&1; then
    echo "install: skipped, because $needed isn't on the PATH"
    exit 0
  fi
done

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
# shellcheck source=tests/lib/assert.sh
. "$ROOT/tests/lib/assert.sh"

# Run from inside a session, these would tie the new ones to it. The rest would let a
# session log in, or point the plugin root elsewhere.
unset CLAUDECODE CLAUDE_CODE_ENTRYPOINT CLAUDE_CODE_SESSION_ID CLAUDE_CODE_CHILD_SESSION \
  CLAUDE_CODE_SESSION_ATTENDED CLAUDE_PID CLAUDE_EFFORT CLAUDE_CODE_MESSAGING_SOCKET \
  CLAUDE_CODE_MESSAGING_TOKEN CLAUDE_AGENT_SDK_VERSION CLAUDE_CODE_EMIT_SESSION_STATE_EVENTS \
  CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_ROOT CLAUDE_CODE_PLUGIN_CACHE_DIR CLAUDE_CODE_PLUGIN_DIRS \
  ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN CLAUDE_CODE_OAUTH_TOKEN CLAUDE_CODE_USE_BEDROCK \
  CLAUDE_CODE_USE_VERTEX CLAUDE_CODE_USE_FOUNDRY

marketplace=claude-code-custom
url=https://git.invalid/claude-code-custom.git
skills='choose-stack conventions-code conventions-ui enable-releases independent-review land maintain screen-check setup'

work=$(tmp_dir)
GIT_CONFIG_GLOBAL=$work/gitconfig
GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL GIT_CONFIG_NOSYSTEM
bare=$work/marketplace.git
git config --file "$GIT_CONFIG_GLOBAL" "url.file://$bare.insteadOf" "$url" ||
  _assert_fail "could not write the test's git config"

# --- the two marketplace snapshots

# HEAD, until the commit that deletes it lands, then that commit's parent.
web_manifest=plugins/web-dev-workflow/.claude-plugin/plugin.json
if git -C "$ROOT" cat-file -e "HEAD:$web_manifest" 2>/dev/null; then
  old=$(git -C "$ROOT" rev-parse HEAD)
else
  old=$(git -C "$ROOT" rev-parse -q --verify "$(git -C "$ROOT" rev-list -1 HEAD -- "$web_manifest")^")
fi
[ -n "$old" ] || _assert_fail "no commit with web-dev-workflow: this test needs the full history"
old_versions=$(git -C "$ROOT" show "$old:plugins/web-dev-workflow/.claude-plugin/plugin.json" | jq -r .version)
old_versions="$old_versions $(git -C "$ROOT" show "$old:plugins/dev-workflow/.claude-plugin/plugin.json" | jq -r .version)"
assert_exit 0 test "$old_versions" = "1.2.0 0.2.0"
new_version=$(jq -r .version "$ROOT/plugins/dev-workflow/.claude-plugin/plugin.json")

source_repo=$work/source
new_repo "$source_repo"
git -C "$ROOT" archive "$old" | tar -xf - -C "$source_repo" || _assert_fail "could not unpack $old"
{ git -C "$source_repo" add -A && git -C "$source_repo" commit -q -m old; } ||
  _assert_fail "could not commit the old marketplace"
git clone -q --bare "$source_repo" "$bare" || _assert_fail "could not make the bare marketplace"
old_commit=$(git -C "$source_repo" rev-parse HEAD)

# This checkout as git would keep it: tracked and untracked files, less ignored and deleted ones.
git -C "$source_repo" rm -rq . || _assert_fail "could not clear the old marketplace"
(
  cd "$ROOT" || exit 1
  git ls-files --cached --others --exclude-standard | while IFS= read -r file; do
    [ -f "$file" ] && printf '%s\n' "$file"
  done | tar -cf - -T - | tar -xf - -C "$source_repo"
) || _assert_fail "could not copy this checkout"
{ git -C "$source_repo" add -A && git -C "$source_repo" commit -q -m new; } ||
  _assert_fail "could not commit the new marketplace"
new_commit=$(git -C "$source_repo" rev-parse HEAD)

# publish <old|new>: what the marketplace's main branch serves.
publish() {
  case $1 in
    old) pu_commit=$old_commit ;;
    *) pu_commit=$new_commit ;;
  esac
  git -C "$source_repo" push -q -f "$bare" "$pu_commit:refs/heads/main" ||
    _assert_fail "could not publish the $1 marketplace"
}

# --- helpers

# machine: sets CLAUDE_CONFIG_DIR to a new config folder, and project to a new repo.
machine() {
  CLAUDE_CONFIG_DIR=$(tmp_dir)
  case $CLAUDE_CONFIG_DIR in
    "$_assert_tmp_root"/*) ;;
    *) _assert_fail "refusing a config folder outside the temp folder: $CLAUDE_CONFIG_DIR" ;;
  esac
  export CLAUDE_CONFIG_DIR
  project="$(tmp_dir)/project"
  new_repo "$project"
  elsewhere="$(tmp_dir)/elsewhere"
  new_repo "$elsewhere"
}

# cc <folder> <claude argument...>: one Claude Code command, run in that folder.
cc() {
  cc_folder=$1
  shift
  (cd "$cc_folder" && claude "$@" </dev/null 2>&1)
}

# cc_ok <folder> <claude argument...>: the same, failing the test if it fails.
cc_ok() {
  cc_output=$(cc "$@") || _assert_fail "claude $* failed: $cc_output"
  printf '%s\n' "$cc_output"
}

# session <folder> [<prompt>]: a session in that folder, setting init to its init event
# and loaded to "<version> <number of its skills>" for dev-workflow, or "none".
session() {
  se_log="$(tmp_dir)/session.jsonl"
  (
    cd "$1" &&
      claude -p "${2:-hi}" --model haiku --max-budget-usd 0.05 --max-turns 1 --strict-mcp-config \
        --output-format stream-json --verbose </dev/null >"$se_log" 2>"$se_log.errors"
  )
  init=$(jq -c 'select(.subtype == "init")' "$se_log" 2>/dev/null)
  [ -n "$init" ] || _assert_fail "a session in $1 didn't start: $(head -c 400 "$se_log.errors")"
  se_cost=$(jq -r 'select(.type == "result") | .total_cost_usd' "$se_log")
  [ "$se_cost" = 0 ] || _assert_fail "a session cost \$$se_cost: this test should spend nothing"
  loaded=$(printf '%s' "$init" | jq -r '
    ([.plugins[] | select(.source == "dev-workflow@claude-code-custom")][0].version) as $v
    | if $v == null then "none"
      else "\($v) \([.skills[] | select(startswith("dev-workflow:"))] | length)" end')
}

# enabled_keys <settings file>: its enabledPlugins keys, one line.
enabled_keys() {
  jq -r '.enabledPlugins // {} | keys | join(" ")' "$1"
}

# records <plugin>: the scopes installed_plugins.json records it at.
records() {
  jq -r --arg id "$1@$marketplace" '.plugins[$id] // [] | [.[].scope] | sort | join(" ")' \
    "$CLAUDE_CONFIG_DIR/plugins/installed_plugins.json"
}

# check_components <folder>: the plugin's details list the nine skills, once each.
check_components() {
  cp_details=$(cc_ok "$1" plugin details "dev-workflow@$marketplace")
  assert_contains "$cp_details" "dev-workflow $new_version"
  cp_line=$(printf '%s\n' "$cp_details" | grep -E '^ *Skills \(')
  cp_names=$(printf '%s\n' "$cp_line" | sed 's/^ *Skills ([0-9]*) *//' | tr ',' '\n' |
    sed 's/^ *//; s/ *$//' | sort | tr '\n' ' ')
  assert_exit 0 test "$cp_names" = "$skills "
  assert_contains "$cp_line" "Skills (9)"
  # Commands would show among the skills, so nine names, once each, means none.
  assert_not_contains "$cp_details" "Commands ("
}

echo "install: $(claude --version), old marketplace $old ($old_versions), new $new_version"

# --- a fresh install

publish new
machine
cc_ok "$elsewhere" plugin marketplace add "$url" >/dev/null
cc_ok "$elsewhere" plugin install "dev-workflow@$marketplace" >/dev/null
assert_exit 0 test "$(records dev-workflow)" = user
check_components "$elsewhere"
session "$project"
assert_exit 0 test "$loaded" = "$new_version 9"
echo "fresh install: loads $loaded skills"
fresh_config=$CLAUDE_CONFIG_DIR
fresh_project=$project

# The same from a local folder, which loads in place.
machine
cc_ok "$elsewhere" plugin marketplace add "$source_repo" >/dev/null
cc_ok "$elsewhere" plugin install "dev-workflow@$marketplace" >/dev/null
check_components "$elsewhere"
session "$project"
assert_exit 0 test "$loaded" = "$new_version 9"
echo "fresh install from a local folder: loads $loaded skills"

# --- web-dev-workflow, installed for the user and for a project

publish old
machine
cc_ok "$elsewhere" plugin marketplace add "$url" >/dev/null
cc_ok "$elsewhere" plugin install "web-dev-workflow@$marketplace" >/dev/null
cc_ok "$project" plugin install "web-dev-workflow@$marketplace" --scope project >/dev/null
assert_exit 0 test "$(records web-dev-workflow)" = "project user"
assert_exit 0 test "$(enabled_keys "$project/.claude/settings.json")" = "web-dev-workflow@$marketplace"
# Old dev-workflow commands show among its skills.
assert_contains "$(cc_ok "$elsewhere" plugin details "web-dev-workflow@$marketplace")" "Skills (2)  setup, setup"

publish new
cc_ok "$project" plugin marketplace update "$marketplace" >/dev/null
session "$project"
# The keys are rewritten in both scopes, and the old plugin's records are gone.
assert_exit 0 test "$(enabled_keys "$CLAUDE_CONFIG_DIR/settings.json")" = "dev-workflow@$marketplace"
assert_exit 0 test "$(enabled_keys "$project/.claude/settings.json")" = "dev-workflow@$marketplace"
assert_exit 0 test -z "$(records web-dev-workflow)"
# "Not cached": dev-workflow is on, but its record has no files behind it, so it doesn't load.
assert_exit 0 test "$loaded" = none
not_cached=$(jq -r --arg id "dev-workflow@$marketplace" \
  '[.plugins[$id] // [] | .[].installPath] | join("\n")' "$CLAUDE_CONFIG_DIR/plugins/installed_plugins.json" |
  while IFS= read -r path; do [ -z "$path" ] || [ -d "$path" ] || echo missing; done)
echo "web-dev-workflow, user and project: after the marketplace update, dev-workflow is on in both" \
  "settings files, recorded at \"$(records dev-workflow)\"${not_cached:+ with its files missing}, and doesn't load"

# What fixes it: one install of the new name.
install_output=$(cc_ok "$elsewhere" plugin install "dev-workflow@$marketplace")
assert_not_contains "$install_output" "downgrade"
assert_exit 0 test "$(records dev-workflow)" = "project user"
session "$project"
assert_exit 0 test "$loaded" = "$new_version 9"
session "$elsewhere"
assert_exit 0 test "$loaded" = "$new_version 9"
check_components "$elsewhere"
echo "  after claude plugin install dev-workflow@$marketplace: loads $loaded skills, in the project and elsewhere"

# --- web-dev-workflow for the user, and a project whose committed settings name it

publish old
machine
mkdir -p "$project/.claude"
printf '{"enabledPlugins": {"web-dev-workflow@%s": true}}\n' "$marketplace" >"$project/.claude/settings.json"
cc_ok "$elsewhere" plugin marketplace add "$url" >/dev/null
cc_ok "$elsewhere" plugin install "web-dev-workflow@$marketplace" >/dev/null

publish new
cc_ok "$elsewhere" plugin marketplace update "$marketplace" >/dev/null
session "$elsewhere"
assert_exit 0 test "$loaded" = none
assert_exit 0 test "$(enabled_keys "$CLAUDE_CONFIG_DIR/settings.json")" = "dev-workflow@$marketplace"
# A project's key is rewritten the first time a session runs there.
assert_exit 0 test "$(enabled_keys "$project/.claude/settings.json")" = "web-dev-workflow@$marketplace"
session "$project"
assert_exit 0 test "$(enabled_keys "$project/.claude/settings.json")" = "dev-workflow@$marketplace"
echo "web-dev-workflow, user only: not loaded after the marketplace update; the project's key rewritten at its first session"

# Here the documented update fixes it too, though it says nothing changed.
update_output=$(cc_ok "$elsewhere" plugin update "dev-workflow@$marketplace")
session "$elsewhere"
assert_exit 0 test "$loaded" = "$new_version 9"
session "$project"
assert_exit 0 test "$loaded" = "$new_version 9"
echo "  after claude plugin update: \"$(printf '%s\n' "$update_output" | tail -n 1)\", and it loads $loaded skills"

# --- dev-workflow 0.2.0

publish old
machine
cc_ok "$elsewhere" plugin marketplace add "$url" >/dev/null
cc_ok "$elsewhere" plugin install "dev-workflow@$marketplace" >/dev/null
assert_exit 0 test "$(jq -r --arg id "dev-workflow@$marketplace" '.plugins[$id][0].version' \
  "$CLAUDE_CONFIG_DIR/plugins/installed_plugins.json")" = 0.2.0
assert_contains "$(cc_ok "$elsewhere" plugin details "dev-workflow@$marketplace")" "dev-workflow 0.2.0"

publish new
cc_ok "$elsewhere" plugin marketplace update "$marketplace" >/dev/null
update_output=$(cc_ok "$elsewhere" plugin update "dev-workflow@$marketplace")
assert_contains "$update_output" "from 0.2.0 to $new_version"
check_components "$elsewhere"
session "$project"
assert_exit 0 test "$loaded" = "$new_version 9"
echo "dev-workflow 0.2.0: \"$(printf '%s\n' "$update_output" | tail -n 1)\", then loads $loaded skills"

# --- `${user_config.*}` in a skill, in the fresh install

CLAUDE_CONFIG_DIR=$fresh_config
export CLAUDE_CONFIG_DIR

# transcript_says <text>: whether a session transcript has the text, which is how the
# skill's content reached it. A session that can't log in still writes one. Each check
# clears the transcripts first.
transcript_says() {
  find "$CLAUDE_CONFIG_DIR/projects" -name '*.jsonl' -exec grep -F -q -- "$1" {} + 2>/dev/null
}

# shellcheck disable=SC2016 # Literal placeholders.
{
  unsaved='every `${user_config.maintenance_interval_days}` days'
  root_unsaved='${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json'
  with_default='every `30` days'
  with_saved='every `14` days'
}
rm -rf "$CLAUDE_CONFIG_DIR/projects"
session "$fresh_project" "/dev-workflow:maintain"
# Never saved: the placeholder stays as written, and the plugin.json default isn't used.
assert_exit 0 transcript_says "$unsaved"
assert_exit 1 transcript_says "$with_default"
# The plugin root, in the same text, is filled in.
assert_exit 1 transcript_says "$root_unsaved"
assert_exit 0 transcript_says "/plugins/cache/$marketplace/dev-workflow/$new_version/.claude-plugin/plugin.json"

printf '{"maintenance_interval_days": "14"}\n' |
  (cd "$fresh_project" && claude plugin configure "dev-workflow@$marketplace" --values-stdin >/dev/null 2>&1) ||
  _assert_fail "could not save a setting"
rm -rf "$CLAUDE_CONFIG_DIR/projects"
session "$fresh_project" "/dev-workflow:maintain"
assert_exit 0 transcript_says "$with_saved"
echo "user_config in a skill: an unsaved option stays a \${user_config.*} placeholder, not its default; a saved one is filled in"
