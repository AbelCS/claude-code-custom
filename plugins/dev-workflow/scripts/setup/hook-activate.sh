#!/bin/sh
# activate_plan <root> <work>: decides how install-hooks.sh turns the hooks in
# .githooks/ on, reporting each file or setting and adding its steps, from what
# detect.sh finds. Returns 2 on an error. Source this file, from install-hooks.sh,
# which has report, step, json_edit and $HOOKS; don't run it.
#
#   husky             a line running each hook, such as .githooks/pre-push "$@", is
#                     added to .husky/<hook>, keeping what's there
#   lefthook,         reported with what to add, as their files aren't this
#   pre-commit,       plugin's to rewrite
#   simple-git-hooks
#   core.hooksPath    set to anything but .githooks: never overwritten, but reported
#                     with what to add to the hooks there
#   package.json      otherwise, a prepare script sets core.hooksPath for every clone,
#                     keeping a prepare that's there, which runs first. It can't fail
#                     an install where there's no git, as in some builds
#   otherwise         core.hooksPath is set to .githooks, now as well with package.json
# Not a git repo: reported, as there's nothing to turn on.

ACTIVATE_PREPARE='git config core.hooksPath .githooks || exit 0'

_activate_lines() { # <prefix>: the line running each hook, under a prefix
  for _hook in $HOOKS; do
    printf '%s%s: .githooks/%s "$@"\n' "$1" "$_hook" "$_hook"
  done
}

_activate_husky() { # <root> <work>
  for _hook in $HOOKS; do
    _file=$1/.husky/$_hook
    _line=".githooks/$_hook \"\$@\""
    if [ -L "$_file" ]; then
      report ".husky/$_hook" conflict "a symlink, so left alone: add this line to it: $_line"
    elif [ ! -e "$_file" ]; then
      printf '%s\n' "$_line" >"$2/husky.$_hook"
      report ".husky/$_hook" create "runs the dev-workflow hook"
      step write "$_file" "$2/husky.$_hook" 1
    elif grep -Fxq -- "$_line" "$_file" 2>/dev/null; then
      report ".husky/$_hook" keep
    else
      [ -f "$_file" ] && [ -r "$_file" ] || {
        printf 'cannot read: %s\n' "$_file" >&2
        return 2
      }
      {
        cat -- "$_file"
        [ ! -s "$_file" ] || [ "$(tail -c 1 "$_file" | od -An -c | tr -d ' ')" = '\n' ] || echo
        printf '%s\n' "$_line"
      } >"$2/husky.$_hook"
      report ".husky/$_hook" update "gets a line running the dev-workflow hook, after what's there"
      step write "$_file" "$2/husky.$_hook" 0
    fi
  done
}

_activate_lefthook() { # <root>
  _config=
  for _name in lefthook .lefthook .config/lefthook; do
    for _ext in yml yaml toml json jsonc; do
      if [ -z "$_config" ] && [ -f "$1/$_name.$_ext" ]; then _config=$_name.$_ext; fi
    done
  done
  [ -n "$_config" ] || _config=lefthook.yml
  _missing=
  for _hook in $HOOKS; do
    grep -Fq -- ".githooks/$_hook" "$1/$_config" 2>/dev/null || _missing="$_missing $_hook"
  done
  if [ -z "$_missing" ]; then
    report "$_config" keep "lefthook runs the dev-workflow hooks"
    return 0
  fi
  report "$_config" conflict "lefthook runs this repo's git hooks, and its config is the project's: add these lines to $_config, merged into any hooks already there, then run lefthook install. In another format than YAML, add the same settings.

pre-commit:
  commands:
    dev-workflow:
      run: .githooks/pre-commit
commit-msg:
  commands:
    dev-workflow:
      run: .githooks/commit-msg {1}
pre-push:
  commands:
    dev-workflow:
      run: .githooks/pre-push {0}
      use_stdin: true"
}

_activate_package() { # <root> <work>
  # shellcheck disable=SC2016 # The dollars are jq's.
  json_edit "$1/package.json" "$2/package.json" '
    if (.scripts // {} | type) != "object" then error("scripts has to be an object") else . end
    | .scripts = ((.scripts // {}) | (.prepare // "") as $old
      | if ($old | contains("git config core.hooksPath .githooks")) then .
        elif $old == "" then .prepare = $cmd
        else .prepare = "\($old) && (\($cmd))" end)
  ' --arg cmd "$ACTIVATE_PREPARE"
  case $? in
    0)
      report package.json update "a prepare script sets core.hooksPath when someone runs npm install"
      step write "$1/package.json" "$2/package.json" 0
      ;;
    1) report package.json keep ;;
    *) return 2 ;;
  esac
}

activate_plan() {
  # shellcheck disable=SC2154 # install-hooks.sh sets here.
  _detected=$(sh "$here/detect.sh" "$1") || return 2
  _git=$(printf '%s\n' "$_detected" | jq -r .git)
  _tool=$(printf '%s\n' "$_detected" | jq -r .hookTool)
  _path=$(printf '%s\n' "$_detected" | jq -r '.hooksPath // ""')

  if [ "$_git" != true ]; then
    report core.hooksPath conflict "not a git repo, so the hooks can't be turned on: run git init, then setup again"
    return 0
  fi
  case $_tool in
    husky) _activate_husky "$1" "$2" || return 2 ;;
    lefthook) _activate_lefthook "$1" ;;
    pre-commit | simple-git-hooks)
      _file=.pre-commit-config.yaml
      [ "$_tool" = pre-commit ] || _file=package.json
      report "$_file" conflict "$_tool runs this repo's git hooks, and its settings are the project's: have it run .githooks/pre-commit, .githooks/commit-msg with the message file's path, and .githooks/pre-push with its two arguments and its stdin."
      ;;
    *)
      case $_path in
        "" | .githooks | .githooks/) ;;
        *)
          report core.hooksPath conflict "core.hooksPath is $_path, which setup leaves alone. To run the dev-workflow hooks too, add a line to each of these hooks, creating it if needed, and pass pre-push its stdin:
$(_activate_lines "  $_path/")"
          return 0
          ;;
      esac
      if [ -f "$1/package.json" ]; then _activate_package "$1" "$2" || return 2; fi
      if [ -n "$_path" ]; then
        report core.hooksPath keep
      else
        report core.hooksPath update "set to .githooks, which turns the hooks on in this clone"
        step hooks-path
      fi
      ;;
  esac
}
