#!/bin/sh
# Usage: ledger.sh hash <file>
#        ledger.sh get <project-file> <key>
#        ledger.sh set <project-file> <key> <hash>
#
# The ledger records a fingerprint of each thing setup wrote, so a rerun can tell
# text the project left alone from text it edited. It lives in the project file's
# "managed" object, keyed by path, with "#<section>" for a part of a file, such as
# "AGENTS.md#workflow".
#
#   hash  prints git's blob hash of the file, without any filters
#   get   prints the key's fingerprint; exits 1 if there is none, or no file yet
#   set   records it, creating the file and its folder if needed, and keeping every
#         other field and the file's mode
#
# Exits 2 on bad usage, a file that can't be read, or a project file that isn't a
# JSON object with an object for "managed". Nothing is written then.

die() {
  printf 'ledger.sh: %s\n' "$*" >&2
  exit 2
}

for tool in git jq; do
  command -v "$tool" >/dev/null 2>&1 || die "missing required tool: $tool"
done

# valid <project-file>: exits 2 unless it's a JSON object with an object managed.
valid() {
  jq -e 'type == "object" and ((.managed // {}) | type == "object")' "$1" >/dev/null 2>&1 ||
    die "not a valid project file: $1"
}

case "${1:-}:$#" in
  hash:2)
    [ -f "$2" ] && [ -r "$2" ] || die "cannot read: $2"
    git hash-object --no-filters -- "$2" || die "cannot hash: $2"
    ;;
  get:3)
    [ -e "$2" ] || exit 1
    valid "$2"
    jq -re --arg k "$3" '.managed[$k] // empty | strings' "$2" || exit 1
    ;;
  set:4)
    # shellcheck source=plugins/dev-workflow/scripts/setup/atomic.sh
    . "$(dirname -- "$0")/atomic.sh"
    if [ -e "$2" ]; then
      valid "$2"
      current=$(cat -- "$2") || die "cannot read: $2"
    else
      mkdir -p -- "$(dirname -- "$2")" || die "cannot create the folder for: $2"
      current='{}'
    fi
    updated=$(printf '%s\n' "$current" | jq --arg k "$3" --arg h "$4" '.managed[$k] = $h') ||
      die "cannot update: $2"
    printf '%s\n' "$updated" | atomic_write "$2" || exit 2
    ;;
  *) die "usage: ledger.sh hash <file> | get <project-file> <key> | set <project-file> <key> <hash>" ;;
esac
