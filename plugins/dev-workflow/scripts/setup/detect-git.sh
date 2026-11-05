#!/bin/sh
# What detect.sh finds about a repo's git and its hooks. Source this file; don't run it.
#
#   detect_git <root>        sets remote, default_branch, hooks_path, hooks_scope and
#                            git_hooks, as detect.sh's fields describe them
#   detect_hook_tool <root>  sets hook_tool, with detect.sh's exists
#   git_hooks_dir <root>     prints the folder git runs hooks from when no hooks path is
#                            in effect: .git/hooks, shared by every worktree

# shellcheck disable=SC2034 # The variables are for detect.sh.

# remote_kind <url>: github only when the host really is github.com.
remote_kind() {
  _url=$(printf '%s' "$1" | LC_ALL=C tr '[:upper:]' '[:lower:]')
  case $_url in
    *://*)
      case ${_url%%://*} in
        http | https | ssh | git | git+ssh | ssh+git) ;;
        *) echo other && return ;;
      esac
      _host=${_url#*://}
      _host=${_host%%[/?#\\]*}
      _host=${_host##*@}
      _host=${_host%%:*}
      ;;
    *:*)
      # The scp form, host:path. A slash before the colon makes it a local path.
      _host=${_url%%:*}
      case $_host in */*) echo other && return ;; esac
      _host=${_host##*@}
      ;;
    *) echo other && return ;;
  esac
  if [ "$_host" = github.com ]; then echo github; else echo other; fi
}

git_hooks_dir() {
  _common=$(git -C "$1" rev-parse --git-common-dir 2>/dev/null) || return 1
  case $_common in /*) ;; *) _common=$1/$_common ;; esac
  printf '%s/hooks\n' "$_common"
}

detect_git() {
  remote=none
  default_branch=main
  hooks_path=
  hooks_scope=
  git_hooks=
  if _url=$(git -C "$1" remote get-url origin 2>/dev/null); then
    remote=$(remote_kind "$_url")
  elif [ -n "$(git -C "$1" remote 2>/dev/null)" ]; then
    remote=other
  fi

  if _ref=$(git -C "$1" symbolic-ref -q refs/remotes/origin/HEAD 2>/dev/null); then
    default_branch=${_ref#refs/remotes/origin/}
  elif [ "$remote" = none ] && _ref=$(git -C "$1" symbolic-ref -q HEAD 2>/dev/null); then
    default_branch=${_ref#refs/heads/}
  fi

  # The value git uses, the last one set, and where it's from: local, worktree, global,
  # system or command, which is the command line and git's environment.
  if _found=$(git -C "$1" config --show-scope --get core.hooksPath 2>/dev/null); then
    _tab=$(printf '\t')
    hooks_scope=${_found%%"$_tab"*}
    hooks_path=${_found#*"$_tab"}
  fi

  # The hooks git runs from .git/hooks: executable files, but git's own samples.
  _dir=$(git_hooks_dir "$1") || return 0
  for _hook in "$_dir"/*; do
    [ -f "$_hook" ] && [ -x "$_hook" ] || continue
    case ${_hook##*/} in *.sample) continue ;; esac
    git_hooks="$git_hooks ${_hook##*/}"
  done
}

detect_hook_tool() {
  hook_tool=none
  _configs=
  for _name in lefthook .lefthook .config/lefthook; do
    for _ext in yml yaml toml json jsonc; do
      _configs="$_configs $_name.$_ext"
    done
  done
  # shellcheck disable=SC2086 # Plain names, split on purpose.
  set -- "$1" $_configs
  _root=$1
  shift
  if [ -d "$_root/.husky" ]; then
    hook_tool=husky
  elif (cd "$_root" && exists "$@"); then
    hook_tool=lefthook
  elif exists "$_root/.pre-commit-config.yaml"; then
    hook_tool=pre-commit
  elif [ -f "$_root/package.json" ] && jq -e '
    objects | has("simple-git-hooks")
      or ([.dependencies, .devDependencies] | map(objects | has("simple-git-hooks")) | any)
  ' "$_root/package.json" >/dev/null 2>&1; then
    hook_tool=simple-git-hooks
  fi
}
