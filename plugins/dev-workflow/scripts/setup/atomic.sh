#!/bin/sh
# atomic_write <target>: replaces target with stdin, all at once. The text goes to
# a temp file in the target's own folder, which is then moved over it, so a reader
# never sees half a file. An existing file keeps its mode; a new one gets the
# umask's. A symlink is refused rather than replaced or written through. Returns 2
# on any failure, leaving the target as it was. Source this file; don't run it.

atomic_write() {
  if [ -L "$1" ]; then
    printf 'atomic_write: is a symlink, not writing: %s\n' "$1" >&2
    return 2
  fi
  _atomic_dir=$(dirname -- "$1")
  # A folder of our own, so the file inside it is created with the umask's mode.
  _atomic_tmp=$(mktemp -d "$_atomic_dir/.dw-write.XXXXXX") || {
    printf 'atomic_write: cannot write in: %s\n' "$_atomic_dir" >&2
    return 2
  }
  if { [ ! -e "$1" ] || cp -p -- "$1" "$_atomic_tmp/file"; } &&
    cat >"$_atomic_tmp/file" &&
    mv -f -- "$_atomic_tmp/file" "$1"; then
    rmdir -- "$_atomic_tmp"
    return 0
  fi
  rm -rf -- "$_atomic_tmp"
  printf 'atomic_write: could not write: %s\n' "$1" >&2
  return 2
}
