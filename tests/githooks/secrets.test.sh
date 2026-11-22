#!/bin/sh
# Tests the pre-commit template's check for secrets, by real commits in a temp repo.
#
# Every secret here is built from pieces at run time, so this file holds none whole: the
# hook guards this repo too, and would refuse to commit it otherwise. They're all fake.

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
# shellcheck source=tests/lib/assert.sh
. "$ROOT/tests/lib/assert.sh"

templates="$ROOT/plugins/dev-workflow/skills/setup/templates/githooks"

GIT_CONFIG_GLOBAL=/dev/null
GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL GIT_CONFIG_NOSYSTEM

repo="$(tmp_dir)/a b/repo"
new_repo "$repo"
hooks="$repo/.githooks"
mkdir -p "$hooks"
cp "$templates/pre-commit" "$templates/dw-lib.sh" "$hooks/"
git -C "$repo" config core.hooksPath .githooks
printf '.githooks\n' >>"$repo/.git/info/exclude"
git -C "$repo" commit -q --allow-empty -m 'chore: start'

write_env() { # [allowed globs, one per line]
  cat >"$hooks/dev-workflow.env" <<ENV
DW_DEFAULT_BRANCH='main'
DW_CHECK='scripts/check'
DW_CI_ALLOWLIST=''
DW_FORMATTERS=''
DW_SECRETS_ALLOW='${1-}'
ENV
}
write_env

# stage <path> <contents>: a fresh index holding just this file.
stage() {
  git -C "$repo" reset -q
  mkdir -p "$(dirname "$repo/$1")"
  printf '%s\n' "$2" >"$repo/$1"
  git -C "$repo" add -- "$1"
}

commit() {
  git -C "$repo" commit -q -m 'feat: x' 2>&1
}

# refuses <path> <contents> <kind>: the commit is refused, naming the file and the kind,
# and the secret's value never shows.
refuses() {
  stage "$1" "$2"
  if out=$(commit); then
    _assert_fail "expected the commit of $1 to be refused"
  fi
  assert_contains "$out" 'pre-commit: '
  assert_contains "$out" "$1"
  assert_contains "$out" "$3"
  assert_not_contains "$out" "$2"
  git -C "$repo" reset -q
  rm -f "$repo/$1"
}

passes() { # <path> <contents>
  stage "$1" "$2"
  out=$(commit) || _assert_fail "expected the commit of $1 to pass: $out"
}

# --- Secrets in what's added

a=ABCDEFGHIJKLMNOPQRSTUVWXYZ
d=0123456789
key_header="-----BEGIN RSA PRIVATE"" KEY-----"
refuses deploy/key.txt "$key_header
MIIEowIBAAKCAQEA" 'private key'
refuses src/aws.ts "const id = 'AK""IA${d}ABCDEF'" 'AWS access key'
refuses src/gh.ts "token: gh""p_${a}${d}abcdefghij" 'GitHub token'
refuses src/gh2.ts "token: github""_pat_${d}${a}abc_${a}" 'GitHub token'
refuses src/slack.ts "x""oxb-${d}-${d}-${a}" 'Slack token'
refuses src/pay.ts "sk_""live_${d}${a}" 'Stripe live key'
refuses src/maps.ts "AI""za${a}${d}abcdefghi" 'Google API key'
refuses src/ai.ts "sk-""ant-api03-${a}${d}" 'Anthropic key'
refuses src/ai2.ts "sk-""proj-${a}${d}" 'OpenAI key'

# --- Files that hold secrets by their nature

refuses .env 'DATABASE_URL=postgres://u:p@h/db' 'secrets file'
refuses config/.env.production 'API=1' 'secrets file'
refuses certs/server.pem 'not a key at all' 'key or certificate file'
refuses certs/server.key 'x' 'key or certificate file'
refuses keys/id_ed25519 'x' 'key or certificate file'
refuses keys/store.p12 'x' 'key or certificate file'

# --- What passes

passes .env.example 'DATABASE_URL=postgres://user:password@localhost/db'
passes config/.env.template 'API='
passes src/app.ts 'const ok = "sk_test_abc"; // not a live key'
passes README.md 'Set AWS_ACCESS_KEY_ID in your shell. Keys start with AKIA.'
# Removing a secret is what should happen, so a removed line never counts.
git -C "$repo" reset -q
printf 'line\n' >"$repo/src/old.ts"
git -C "$repo" add src/old.ts
git -C "$repo" commit -q --no-verify -m 'chore: an old file'
printf '%s\n' "sk_""live_${d}${a}" >"$repo/src/old.ts"
git -C "$repo" add src/old.ts
git -C "$repo" commit -q --no-verify -m 'chore: the secret, from before the hook'
printf 'line\n' >"$repo/src/old.ts"
git -C "$repo" add src/old.ts
out=$(commit) || _assert_fail "removing a secret should pass: $out"

# A line whose content starts with ++ is still added content.
refuses src/plus.ts "++ sk_""live_${d}${a}" 'Stripe live key'

# A file git is told not to diff is still read as text.
git -C "$repo" reset -q
printf 'gen/*.txt -diff\n' >"$repo/.gitattributes"
git -C "$repo" add .gitattributes
git -C "$repo" commit -q --no-verify -m 'chore: attributes'
refuses gen/out.txt "sk_""live_${d}${a}" 'Stripe live key'

# A placeholder in docs isn't a token.
passes docs/slack.md 'Set SLACK_TOKEN to xo''xb-your-bot-token'

# A refused secret stops the hook there: a formatter that echoes what it's given, as
# an error frame would, never runs to print it.
cat >"$repo/echo-fmt" <<'FMT'
#!/bin/sh
cat "$@"
exit 1
FMT
chmod +x "$repo/echo-fmt"
printf 'echo-fmt\n' >>"$repo/.git/info/exclude"
cat >"$hooks/dev-workflow.env" <<ENV
DW_DEFAULT_BRANCH='main'
DW_CHECK='scripts/check'
DW_CI_ALLOWLIST=''
DW_FORMATTERS='*.ts|./echo-fmt'
DW_SECRETS_ALLOW=''
ENV
token="sk_""live_${d}${a}"
stage src/shown.ts "const key = '$token'"
out=$(commit) && _assert_fail "expected the commit of src/shown.ts to be refused"
assert_contains "$out" 'Stripe live key'
assert_not_contains "$out" "$token"
git -C "$repo" reset -q
rm -f "$repo/src/shown.ts"
write_env

# The message gives the path as a glob that matches only it, so pasting it into the
# allowlist can't let a neighbour through.
stage 'app/users/[id]/fixture.ts' "k: sk_""live_${d}${a}"
out=$(commit) && _assert_fail "expected the commit to be refused"
assert_contains "$out" 'app/users/\[id\]/fixture.ts'
git -C "$repo" reset -q
write_env 'app/users/\[id\]/fixture.ts'
passes 'app/users/[id]/fixture.ts' "k: sk_""live_${d}${a}"
refuses app/users/i/fixture.ts "k: sk_""live_${d}${a}" 'Stripe live key'
write_env

# --- A path the project allows

write_env 'tests/fixtures/*
*.example.pem'
passes tests/fixtures/sample.ts "fake: sk_""live_${d}${a}"
passes certs/test.example.pem 'x'
refuses src/pay2.ts "sk_""live_${d}${a}" 'Stripe live key'
write_env

# An env file from before this check, without DW_SECRETS_ALLOW, still checks, with
# nothing allowed.
cat >"$hooks/dev-workflow.env" <<'ENV'
DW_DEFAULT_BRANCH='main'
DW_CHECK='scripts/check'
DW_CI_ALLOWLIST=''
DW_FORMATTERS=''
ENV
refuses src/pay3.ts "sk_""live_${d}${a}" 'Stripe live key'
write_env

# --- The template needs nothing a git hook can't have

assert_exit 1 grep -Ewq 'jq|node|python3?' "$templates/pre-commit"
