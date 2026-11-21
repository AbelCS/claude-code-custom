#!/bin/sh
# The release-please templates that enable-releases writes: tags hold the bare version,
# like 1.4.0, the same as the tags land adds when release-please isn't used.

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
# shellcheck source=tests/lib/assert.sh
. "$ROOT/tests/lib/assert.sh"

config="$ROOT/plugins/dev-workflow/skills/enable-releases/templates/release-please-config.json"

assert_exit 0 jq -e '.packages["."]["include-v-in-tag"] == false' "$config"
assert_exit 0 jq -e '.packages["."]["include-component-in-tag"] == false' "$config"
