#!/bin/sh
# Where a path in the project really leads, so setup never reads or writes through a
# symlink to somewhere outside it, as a hostile repo could link a file setup copies
# to a private file elsewhere. POSIX only: cd -P and pwd -P resolve the folders, as
# readlink -f and realpath aren't everywhere. Source this file; don't run it.

# path_physical <dir>: prints the folder's path with every symlink in it resolved.
path_physical() {
  (CDPATH='' cd -P -- "$1" 2>/dev/null && pwd -P)
}

# path_link_is <link> <file>: whether link is a symlink whose own target is file, a
# regular file that isn't a link itself, compared by where both really are. Only the
# link's target is looked at, never what's in it, so a chain of links or a dangling
# one is never the file.
path_link_is() {
  [ -L "$1" ] && [ -f "$2" ] && [ ! -L "$2" ] || return 1
  _path_to=$(readlink -- "$1") || return 1
  case $_path_to in
    '' | */ | . | .. | */. | */..) return 1 ;;
    /*) ;;
    *) _path_to=$(dirname -- "$1")/$_path_to ;;
  esac
  _path_got=$(path_physical "$(dirname -- "$_path_to")") || return 1
  _path_want=$(path_physical "$(dirname -- "$2")") || return 1
  [ "$_path_got/${_path_to##*/}" = "$_path_want/${2##*/}" ]
}

# path_inside <root> <relative path>: whether the folder the path is in, or the
# nearest of its folders that's there, really is inside root. A folder that's a
# dangling symlink doesn't count as inside, as where it leads can't be known. The
# path itself isn't followed: callers refuse a symlink there on their own.
path_inside() {
  _path_root=$(path_physical "$1") || return 1
  _path_at=$(dirname -- "$1/$2")
  while [ ! -e "$_path_at" ] && [ ! -L "$_path_at" ]; do
    _path_at=$(dirname -- "$_path_at")
  done
  _path_real=$(path_physical "$_path_at") || return 1
  case $_path_real/ in "$_path_root"/*) return 0 ;; esac
  return 1
}

# path_check <root> <relative paths...>: path_inside for each, printing which one
# isn't and returning 2.
path_check() {
  _path_base=$1
  shift
  for _path_rel in "$@"; do
    path_inside "$_path_base" "$_path_rel" && continue
    printf '%s is reached through a symlink to outside the project, so setup will not read or write it: replace the link with a folder, then run setup again\n' \
      "$_path_rel" >&2
    return 2
  done
}
