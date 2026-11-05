#!/bin/sh
# run.sh's helpers: copy_in and only_old_blocks, for the plan worked out on a copy,
# and line, docs, plugins, github and merge_lines. Source this file, from run.sh, which
# has $root, $templates, $tools, $detected, $work, $here, $CLAUDE, approved, path_link_is
# and agents; don't run it.

# shellcheck disable=SC2154 # run.sh sets these.

# copy_in <from> <to> <names...>: copies each that's there, a symlink as one pointing
# where the original does: a link to <from>'s AGENTS.md to the copy's, and any other
# to its target in <from>, so the copy still sees each as what it is.
copy_in() {
  _from=$1
  _to=$2
  shift 2
  for _name in "$@"; do
    [ -e "$_from/$_name" ] || [ -L "$_from/$_name" ] || continue
    mkdir -p -- "$(dirname -- "$_to/$_name")" || return 2
    if path_link_is "$_from/$_name" "$_from/AGENTS.md"; then
      ln -s -- "$_to/AGENTS.md" "$_to/$_name" || return 2
    elif [ -L "$_from/$_name" ]; then
      _target=$(readlink -- "$_from/$_name") || return 2
      case $_target in /*) ;; *) _target=$(dirname -- "$_from/$_name")/$_target ;; esac
      ln -s -- "$_target" "$_to/$_name" || return 2
    else
      cp -R -p -- "$_from/$_name" "$_to/$_name" || return 2
    fi
  done
}

# only_old_blocks <dir>: whether AGENTS.md is new and CLAUDE.md's text, moved into it,
# would be nothing but old blocks, which agents-md.sh replaces. Tried on a copy.
only_old_blocks() {
  [ ! -L "$1/AGENTS.md" ] || return 1
  if [ -e "$1/AGENTS.md" ] && grep -q '[^[:space:]]' "$1/AGENTS.md"; then return 1; fi
  rm -rf "$work/probe" && mkdir "$work/probe" || return 1
  copy_in "$1" "$work/probe" CLAUDE.md || return 1
  sh "$here/claude-md.sh" apply "$work/probe" >/dev/null 2>&1 || return 1
  [ -f "$work/probe/AGENTS.md" ] || return 1
  sh "$here/agents-md.sh" apply "$work/probe" "$templates/agents" >/dev/null 2>&1 || return 1
  ! awk '/^<!-- dev-workflow:begin /{ skip = 1 } !skip { print } /^<!-- dev-workflow:end /{ skip = 0 }' \
    "$work/probe/AGENTS.md" | grep -q '[^[:space:]]'
}

line() { # <path> <action> [detail]
  jq -cn --arg p "$1" --arg a "$2" --arg d "${3:-}" '{path: $p, action: $a, detail: $d}'
}

# docs <mode> <out>: step 6.
docs() {
  for _d in docs/superpowers/specs docs/superpowers/plans; do
    if [ -d "$root/$_d" ]; then
      line "$_d" keep
    elif [ -e "$root/$_d" ] || [ -L "$root/$_d" ]; then
      line "$_d" conflict "there, but not a folder, so left alone"
    else
      line "$_d" create "with a .gitkeep, so git keeps the empty folder"
      if [ "$1" = apply ]; then
        mkdir -p -- "$root/$_d" && : >"$root/$_d/.gitkeep" || return 2
      fi
    fi
  done >>"$2"
  for _f in decisions maintenance; do
    _path=docs/$_f.md
    if [ -f "$root/$_path" ]; then
      line "$_path" keep
    elif [ -e "$root/$_path" ] || [ -L "$root/$_path" ]; then
      line "$_path" conflict "there, but not a file, so left alone"
    else
      line "$_path" create
      if [ "$1" = apply ]; then
        mkdir -p -- "$root/docs" && cp -- "$templates/docs/$_f.md" "$root/$_path" || return 2
      fi
    fi
  done >>"$2"
}

# plugins <mode> <project-file> <out>: step 7.
plugins() {
  approved installPlugins || return 0
  _screens=$(jq -r '.hasScreens == true' "$2" 2>/dev/null)
  printf '%s\n' "$tools" | jq -r --argjson screens "${_screens:-false}" '.plugins[]
    | select((.present | not) and (.when == "always" or $screens))
    | [.name, (.marketplace // "-"), .id, .install] | join("\t")' >"$work/plugins" || return 2
  while IFS=$(printf '\t') read -r _name _market _id _install; do
    if [ "$1" = plan ]; then
      line "plugin:$_name" create "$_install"
      continue
    fi
    [ "$_market" = - ] || "$CLAUDE" plugin marketplace add "$_market" >/dev/null 2>&1
    if "$CLAUDE" plugin install "$_id" >"$work/install.out" 2>&1; then
      line "plugin:$_name" create "$_install"
    else
      line "plugin:$_name" conflict "couldn't install it: $(cat "$work/install.out"). Run: $_install"
    fi
  done <"$work/plugins" >>"$3"
}

# github <mode> <out>: step 8.
github() {
  approved githubSettings || return 0
  if [ "$(printf '%s\n' "$detected" | jq -r .remote)" != github ]; then
    line github conflict "origin isn't on GitHub, so no GitHub settings were changed" >>"$2"
    return 0
  fi
  _slug=$(git -C "$root" remote get-url origin 2>/dev/null |
    sed -E 's#^.*[Gg][Ii][Tt][Hh][Uu][Bb]\.[Cc][Oo][Mm][:/]+##; s#/+$##; s#\.git$##')
  _plan=
  [ "$1" = apply ] || _plan=--plan
  if ! sh "$here/github-settings.sh" $_plan "$_slug" >>"$2" 2>"$work/github.err"; then
    line "github:$_slug" conflict "$(cat "$work/github.err")" >>"$2"
  fi
}

# Every line for one path becomes one: the strongest action, and every detail.
merge_lines() {
  jq -sc 'def rank: {keep: 0, update: 1, create: 2, conflict: 3}[.];
    reduce .[] as $l ({order: [], by: {}};
      ($l.detail // "") as $d
      | if .by[$l.path] == null then
          .order += [$l.path] | .by[$l.path] = {path: $l.path, action: $l.action, detail: $d}
        else
          .by[$l.path] |= (
            (if ($l.action | rank) > (.action | rank) then .action = $l.action else . end)
            | if $d == "" or $d == .detail then .
              elif .detail == "" then .detail = $d
              else .detail += "\n" + $d end)
        end)
    | .order[] as $p | .by[$p]' "$1"
}
