#!/bin/sh
# Tests the CI trigger detector and what counts as a workflow, shape by shape. pre-commit
# and the workflow edit hook both use them, and their tests run a few real cases each. The
# detector needs no repo, so this long table costs almost nothing to run.

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
# shellcheck source=tests/lib/assert.sh
. "$ROOT/tests/lib/assert.sh"
# shellcheck source=plugins/dev-workflow/skills/setup/templates/githooks/dw-lib.sh
. "$ROOT/plugins/dev-workflow/skills/setup/templates/githooks/dw-lib.sh"

triggers_of() { # <file content>: sets _found.
  _found=$(dw_ci_triggers "$1") || _assert_fail "the detector failed on: $1"
}

detects() { # <triggers, one per line> <file content>
  triggers_of "$2"
  [ "$_found" = "$1" ] || _assert_fail "expected \"$1\", got \"$_found\" for: $2"
}

clean() { # <file content>
  detects '' "$1"
}

unreadable() { # <file content>
  triggers_of "$1"
  dw_in_lines '?' "$_found" || _assert_fail "expected it to be unreadable, got \"$_found\" for: $1"
}

jobs='jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - run: echo hi'

# --- The detector

# Scalars.
detects pull_request 'on: pull_request'
detects pull_request_target 'on: pull_request_target'
detects push 'on: push'
detects push 'on: "push"'
detects push "on: 'push'"
detects push 'on: push # for now'
detects push '"on": push'
detects push "'on': push"
detects push 'on : push'
detects push 'on:	push'
detects push "name: x

# A comment
on: push
$jobs"
detects push 'on:
  push'
detects push '---
on: push'

# Flow sequences.
detects push 'on: [push]'
detects push 'on: [ workflow_dispatch, push ]'
detects pull_request 'on: ["workflow_dispatch", "pull_request"]'
detects pull_request "on: ['pull_request']"
detects push 'on: [push] # for now'
detects push 'on:
  [push]'
detects push "on: [
  workflow_dispatch,
  push,
]
$jobs"

# Flow maps.
detects pull_request 'on: { pull_request: {} }'
detects pull_request 'on: {pull_request: {}}'
detects pull_request 'on: {pull_request:{}}'
detects pull_request 'on: {"pull_request": null}'
detects push 'on: { push }'
detects push 'on: { push: { branches: [main] } }'
detects push 'on: { workflow_dispatch: { inputs: { a: {} } }, push: {} }'
detects push "on: {
  workflow_dispatch: {},
  # A comment
  push: {
    branches: [main]
  }
}
$jobs"

# Block maps.
detects push "on:
  push:
$jobs"
detects push "on:
  push:
    branches: [main]
$jobs"
detects pull_request "on:
  workflow_dispatch:
  pull_request:
    types: [opened]
$jobs"
detects pull_request_target "on:
    # A comment
    pull_request_target: {}
$jobs"
detects push 'on:
  "push":'
detects push 'on:
  push : {}'
detects push "on: # all of these

  # A comment
  schedule:
    - cron: '0 0 * * *'

  push:
$jobs"

# Block sequences, which YAML lets sit at the same indent as their key.
detects push "on:
  - workflow_dispatch
  - push
$jobs"
detects push "on:
- workflow_dispatch
- push
$jobs"
detects push 'on:
  - "push" # for now'

# A file indented as a whole, a BOM and Windows line endings are all still YAML.
detects push '  name: x
  on: push'
detects push "$(printf '\357\273\277on: push')"
detects push "$(printf 'name: x\r\non: push\r')"
detects push "$(printf 'on:\r\n  push:\r\n    branches: [main]\r')"
detects push "$(printf 'on: [\r\n  push\r\n]\r')"

# Allowed triggers.
clean 'on: workflow_dispatch'
clean "on: workflow_dispatch
$jobs"
clean 'on: [workflow_dispatch, schedule]'
clean 'on: { workflow_dispatch: {} }'
clean "on:
  workflow_dispatch:
  schedule:
    - cron: '0 0 * * *'
$jobs"
clean "on:
- workflow_dispatch
$jobs"
clean 'on:'
clean "name: no trigger at all
$jobs"

# Other triggers that only start the same.
clean 'on: pull_request_review'
clean 'on: [pull_request_review_comment, pushed]'
clean 'on: { pull_request_review: {} }'
clean 'on:
  pull_request_review:
  pushes:'

# The words elsewhere in a workflow.
clean "name: push
on: workflow_dispatch
jobs:
  push:
    name: pull_request
    runs-on: ubuntu-latest
    if: github.event_name == 'push'
    steps:
      - name: push
        run: git push
      - name: on push
        run: echo 'on: push'
      - run: |
          on: push
          push:
          pull_request:
      - uses: some/action@v1
        with:
          on: push
          push: true"
clean 'name: |
  on: push
on: workflow_dispatch'
clean 'env:
  on: push
on: workflow_dispatch'
# A job comes after the triggers, at the indent of a list that has ended.
clean 'on:
- workflow_dispatch
push:
- not a trigger'

# Names further down inside a trigger aren't triggers.
clean "on:
  workflow_dispatch:
    inputs:
      push:
        description: push it
      pull_request:
        type: string
$jobs"
clean 'on:
  workflow_run:
    workflows: [push]
    types:
      - push'
clean 'on: { workflow_dispatch: { inputs: { push: {}, pull_request: { type: string } } } }'
clean 'on: { workflow_dispatch: push }'
clean 'on: [ [push] ]'

# Inside quotes, brackets and commas are text.
clean 'on: [ "a, push" ]'
clean "on: { 'a, push': {} }"
detects push 'on: [ "]", push ]'
detects push "on: { '}': {}, push: {} }"
detects push 'on: [ "a\", b]", push ]'

# Comments don't count.
clean '# on: push
on: workflow_dispatch'
clean 'on: workflow_dispatch # or push
# push:'
clean "on:
  # push:
  workflow_dispatch: # push:
    # pull_request:
$jobs"
clean 'on:
  # - push
  - workflow_dispatch
  # - pull_request'
clean 'on: [
  # push,
  workflow_dispatch # , push
]'
clean 'on: {
  # push: {},
  workflow_dispatch: {} # , push: {}
}'

# A colon can follow a closing quote directly, and a quoted name is the whole name.
detects push 'on: {"push":null}'
detects push "on: {'push':null}"
detects push 'on: {"push" : null}'
detects push '"on":push'
detects push 'on:
  "push":null'
clean 'on: ["push: x"]'
clean 'on: {"a":"push"}'

# A list item's value can start on the next line.
detects push 'on:
  -
    push'
detects push 'on:
-
  push:
    branches: [main]
jobs:
  build: {}'
clean 'on:
  -
    workflow_dispatch
  -
    schedule:
      - push'

# Shapes this can't follow are unreadable, because they could be hiding anything.
for start in '*x' '|' '|-' '>' '>-' '&a' '&a push' '!!str' '!!str push' '? push' '<<: *x'; do
  unreadable "on: $start"
  unreadable "on:
  $start
  push:"
  unreadable "on:
  workflow_dispatch:
  $start"
  unreadable "on:
  - $start"
  unreadable "on:
- workflow_dispatch
- $start"
  unreadable "on:
  -
    $start"
  unreadable "on: [$start]"
  unreadable "on: [workflow_dispatch, $start]"
  unreadable "on: {$start}"
done
unreadable 'on: >-
  push'
unreadable 'on:
  &a push:
    branches: [main]'
unreadable 'on:
  !!str push:'

# A file that's one flow map, wherever it starts.
unreadable '{on: push, jobs: {}}'
unreadable '--- {on: push}'
unreadable '---
# A comment
{
  on: workflow_dispatch
}'
unreadable '  {on: push}'

# As text in quotes, or below the triggers, these characters mean nothing.
clean 'on: ["*x", "&a", "? b"]'
clean 'on: "*x"'
clean "on:
  workflow_dispatch:
    inputs:
      a:
        description: >-
          *x
        default: &a push
$jobs"
clean "name: |
  text
on: workflow_dispatch
env: &e
  a: *x
$jobs"

# Each trigger once, in the order the file has them, whatever it holds besides.
detects 'push
pull_request
pull_request_target' 'on: [push, pull_request, pull_request_target, pull_request]'
detects 'pull_request
push' 'on:
  pull_request:
  workflow_dispatch:
  push:
  pull_request:'
detects 'push
?' 'on: [push, *x]'

# --- What's a workflow: both extensions, and only where GitHub runs them

for path in \
  .github/workflows/x.yml \
  .github/workflows/x.yaml \
  '.github/workflows/a b.yml' \
  .github/workflows/release.yml.yml; do
  assert_exit 0 dw_is_workflow "$path"
done
for path in \
  .github/workflows/sub/x.yml \
  .github/x.yml \
  docs/.github/workflows/x.yml \
  x.yml \
  .github/workflows/x.txt \
  .github/workflows/x.yml.bak \
  .github/workflows/; do
  assert_exit 1 dw_is_workflow "$path"
done

# --- dw_in_lines takes whole lines

lines='.github/workflows/release.yml
.github/workflows/other.yml'
assert_exit 0 dw_in_lines .github/workflows/release.yml "$lines"
assert_exit 0 dw_in_lines .github/workflows/other.yml "$lines"
for near in .github/workflows/lease.yml .github/workflows/release.yml.yml .github/workflows/elease.yml ''; do
  assert_exit 1 dw_in_lines "$near" "$lines"
done
assert_exit 1 dw_in_lines x ''
