#!/bin/sh
# json_format and json_edit write JSON the way Prettier prints it by default, so a
# project that checks its files with Prettier passes right after setup. The expected
# texts are Prettier 3.9.10's own output for the same input.

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
# shellcheck source=tests/lib/assert.sh
. "$ROOT/tests/lib/assert.sh"

here="$ROOT/plugins/dev-workflow/scripts/setup"
# shellcheck source=plugins/dev-workflow/scripts/setup/json.sh
. "$here/json.sh"
work=$(tmp_dir)

formats() { # <name>: <name>.in formatted is <name>.expected, and stays so
  json_format <"$work/$1.in" >"$work/$1.out" || _assert_fail "json_format failed on $1"
  cmp -s "$work/$1.out" "$work/$1.expected" || _assert_fail "$1 isn't in Prettier's form:
$(diff -u "$work/$1.expected" "$work/$1.out")"
  json_format <"$work/$1.expected" >"$work/$1.again" && assert_file_same "$work/$1.again" "$work/$1.expected"
}

# --- an array fits on its line at 80 columns, counting its comma; one more breaks it

cat >"$work/width.in" <<'EOF'
{
  "a": [
    "1234567890123456789012345678901234567890123456789012345678901234567"
  ],
  "b": [
    "12345678901234567890123456789012345678901234567890123456789012345678"
  ],
  "c": {
    "d": [
      "x",
      "y"
    ]
  },
  "e": [],
  "f": {},
  "g": [
    {
      "x": 1
    }
  ],
  "last": [
    "12345678901234567890123456789012345678901234567890123456789012345678"
  ]
}
EOF
cat >"$work/width.expected" <<'EOF'
{
  "a": ["1234567890123456789012345678901234567890123456789012345678901234567"],
  "b": ["12345678901234567890123456789012345678901234567890123456789012345678"],
  "c": {
    "d": ["x", "y"]
  },
  "e": [],
  "f": {},
  "g": [
    {
      "x": 1
    }
  ],
  "last": [
    "12345678901234567890123456789012345678901234567890123456789012345678"
  ]
}
EOF
formats width

# --- objects always open, arrays of objects broken, escapes kept, empty ones closed

cat >"$work/kinds.in" <<'EOF'
{"name":"x","tabs":[1,2],"deep":{"list":["aaaaaaaaaaaaaaaaaaaa","bbbbbbbbbbbbbbbbbbbb","cccccccccccccccccc"],"ok":[true,false,null,"q\"uote"]},"objs":[{"a":"1","b":"2"},{"c":"3"}],"emptyArr":[],"nested":{"x":{}}}
EOF
cat >"$work/kinds.expected" <<'EOF'
{
  "name": "x",
  "tabs": [1, 2],
  "deep": {
    "list": [
      "aaaaaaaaaaaaaaaaaaaa",
      "bbbbbbbbbbbbbbbbbbbb",
      "cccccccccccccccccc"
    ],
    "ok": [true, false, null, "q\"uote"]
  },
  "objs": [
    {
      "a": "1",
      "b": "2"
    },
    {
      "c": "3"
    }
  ],
  "emptyArr": [],
  "nested": {
    "x": {}
  }
}
EOF
formats kinds

# --- with tabs, as a file indented with them keeps them

json_format "$(printf '\t')" <"$work/kinds.in" >"$work/tabs.out"
assert_exit 0 test "$(sed -n 3p "$work/tabs.out")" = "$(printf '\t"tabs": [1, 2],')"

# --- json_edit: a new file in that form, and an edit keeps an existing file's indent

json_edit "$work/none.json" "$work/new.json" '.a = ["x", "y"]'
assert_exit 0 test "$(cat "$work/new.json")" = "$(printf '{\n  "a": ["x", "y"]\n}')"
printf '{\n    "keep": [\n        1\n    ]\n}\n' >"$work/four.json"
json_edit "$work/four.json" "$work/four.out" '.b = {}'
assert_exit 0 test "$(cat "$work/four.out")" = "$(printf '{\n    "keep": [1],\n    "b": {}\n}')"

# --- package.json, package-lock.json and composer.json: Prettier prints them as
# JSON.stringify does, with every item of an array on its own line

for name in package.json package-lock.json composer.json; do
  mkdir -p "$work/$name.d"
  printf '{\n  "keywords": ["a", "b"]\n}\n' >"$work/$name.d/$name"
  json_edit "$work/$name.d/$name" "$work/$name.d/out" '.empty = []'
  assert_exit 0 test "$(cat "$work/$name.d/out")" = "$(printf '{\n  "keywords": [\n    "a",\n    "b"\n  ],\n  "empty": []\n}')"
done
