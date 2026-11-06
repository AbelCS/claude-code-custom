#!/bin/sh
# Tests the marketplace manifest and the release it carries: one plugin, the rename
# that moves old installs to it, author details, and the version kept in one place.

ROOT=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=tests/lib/assert.sh
. "$ROOT/tests/lib/assert.sh"

marketplace="$ROOT/.claude-plugin/marketplace.json"
manifest="$ROOT/plugins/dev-workflow/.claude-plugin/plugin.json"

# --- marketplace.json

# Only dev-workflow is listed, from its folder, with author and description.
assert_exit 0 jq -e '
  ([.plugins[].name] == ["dev-workflow"])
  and (.plugins[0].source == "./plugins/dev-workflow")
  and (.plugins[0].author.name == "AbelCS")
  and (.plugins[0].description | type == "string" and length > 0)
  and (.owner.name == "AbelCS")
' "$marketplace"

# The old plugin's installs move to dev-workflow, and nothing else is renamed.
assert_exit 0 jq -e '.renames == {"web-dev-workflow": "dev-workflow"}' "$marketplace"
# The rename covers the removed plugin, so nothing is force-removed.
assert_exit 0 jq -e 'has("forceRemoveDeletedPlugins") | not' "$marketplace"

# The version lives in plugin.json only: in both, the marketplace's is silently ignored.
assert_exit 0 jq -e '[.plugins[] | has("version")] | any | not' "$marketplace"

# --- plugin.json

assert_exit 0 jq -e '
  .version == "1.0.0"
  and .license == "MIT"
  and .author == {"name": "AbelCS"}
' "$manifest"

# The README says MIT, and the licence it names is there.
assert_exit 0 test -f "$ROOT/LICENSE"
assert_exit 0 grep -q '^MIT License$' "$ROOT/LICENSE"
assert_exit 0 grep -q 'Copyright (c) 2026 AbelCS' "$ROOT/LICENSE"

# --- the old plugin is gone

assert_exit 1 test -e "$ROOT/plugins/web-dev-workflow"
assert_exit 1 test -e "$ROOT/plugins/dev-workflow/commands"
