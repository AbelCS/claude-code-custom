#!/bin/sh
# newer-models.sh: maintain's report of a newer reviewer or second-opinion model, from the
# same code as the session-start check, which tests/hooks/session-start.test.sh covers in
# full. This checks the way in: settings on stdin, placeholders and blanks as defaults.

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
# shellcheck source=tests/lib/assert.sh
. "$ROOT/tests/lib/assert.sh"

NM="$ROOT/plugins/dev-workflow/scripts/maintain/newer-models.sh"
manifest="$ROOT/plugins/dev-workflow/.claude-plugin/plugin.json"
default_reviewer=$(jq -r '.userConfig.reviewer_command.default' "$manifest")
default_alt=$(jq -r '.userConfig.model_noncoding_alt.default' "$manifest")

codex_home() { # <slug...>: a Codex folder whose model cache lists these.
  ch_dir=$(tmp_dir)
  jq -n '{fetched_at: "2026-11-20T00:00:00Z", models: ($ARGS.positional | map({slug: ., display_name: ., visibility: "list"}))}' \
    --args "$@" >"$ch_dir/models_cache.json"
  printf '%s\n' "$ch_dir"
}

run() { # <reviewer command> <alt model>: in the skill's order, the model first, as the
  # command can run over more than one line.
  printf '%s\n%s\n' "$2" "$1" | sh "$NM"
}

CODEX_HOME=$(codex_home gpt-6.9-sol gpt-6.10-sol gpt-6.2-astra gpt-6.3-astra)
export CODEX_HOME

# Saved settings, as the skill passes them: the reviewer's model is the one after -m.
out=$(run 'codex exec -m gpt-6.9-sol --sandbox read-only "<brief>" < /dev/null' gpt-6.2-astra)
assert_contains "$out" 'gpt-6.10-sol is available; the reviewer uses gpt-6.9-sol. Change reviewer_command and reviewer_name in /config.'
assert_contains "$out" 'gpt-6.3-astra is available; the second-opinion model uses gpt-6.2-astra. Change model_noncoding_alt in /config.'
assert_exit 0 test "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = 2

# A command over two lines, with a continuation, is still one setting.
out=$(run 'codex exec \
  -m gpt-6.9-sol --sandbox read-only' gpt-6.2-astra)
assert_contains "$out" 'gpt-6.10-sol is available; the reviewer uses gpt-6.9-sol.'
assert_contains "$out" 'the second-opinion model uses gpt-6.2-astra.'

# Unsaved settings reach the skill as placeholders, or nothing: the defaults count then.
# shellcheck disable=SC2016 # The placeholders are literal.
placeholder_out=$(run '${user_config.reviewer_command}' '${user_config.model_noncoding_alt}')
blank_out=$(run '' '')
default_out=$(run "$default_reviewer" "$default_alt")
assert_exit 0 test "$placeholder_out" = "$default_out"
assert_exit 0 test "$blank_out" = "$default_out"

# Nothing newer, or no Codex: nothing to say.
CODEX_HOME=$(codex_home gpt-6.9-sol gpt-6.2-astra)
assert_exit 0 test -z "$(run 'codex exec -m gpt-6.9-sol' gpt-6.2-astra)"
CODEX_HOME=$(tmp_dir)
assert_exit 0 test -z "$(run 'codex exec -m gpt-6.9-sol' gpt-6.2-astra)"

