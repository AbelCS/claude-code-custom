#!/bin/sh
# activate_plan <root> <work>: decides how install-hooks.sh turns the hooks in
# .githooks/ on, reporting each file or setting and adding its steps, from what
# detect.sh finds. Returns 2 on an error. Source this file, from install-hooks.sh,
# which has report, step, is_hook, json_edit, $HOOKS and $here; don't run it.
#
#   husky             a block running each hook is added at the start of
#                     .husky/<hook>, keeping what's there: hook-husky.sh
#   lefthook,         reported with what to add, as their files aren't this
#   pre-commit,       plugin's to rewrite
#   simple-git-hooks
#   core.hooksPath    in effect from any git config, the repo's or the person's own,
#                     and anything but .githooks: never overwritten, but reported with
#                     what to add to the hooks there
#   .git/hooks        holding executable hooks, which .githooks would stop: reported,
#                     and the hooks left off, or with the person's yes moved into
#                     .githooks first: hook-move.sh
#   package.json      otherwise, a prepare script sets core.hooksPath for every clone,
#                     keeping a prepare that's there, which runs first. It can't fail
#                     an install where there's no git, as in some builds
#   otherwise         core.hooksPath is set to .githooks, now as well with package.json
# Not a git repo: reported, as there's nothing to turn on.

# shellcheck disable=SC2154 # install-hooks.sh sets here.
# shellcheck source=plugins/dev-workflow/scripts/setup/hook-husky.sh
. "$here/hook-husky.sh"
# shellcheck source=plugins/dev-workflow/scripts/setup/hook-move.sh
. "$here/hook-move.sh"

ACTIVATE_PREPARE='git config core.hooksPath .githooks || exit 0'

_activate_lines() { # <prefix>: the line running each hook, under a prefix
  for _hook in $HOOKS; do
    printf '%s%s: .githooks/%s "$@"\n' "$1" "$_hook" "$_hook"
  done
}

_activate_guarded() { # <prefix>: the same, skipping a repo without the hook
  for _hook in $HOOKS; do
    printf '%s%s: [ ! -x .githooks/%s ] || .githooks/%s "$@" || exit\n' "$1" "$_hook" "$_hook" "$_hook"
  done
}

_activate_other_path() { # <path> <scope>
  case $2 in
    local | worktree)
      report core.hooksPath conflict "core.hooksPath is $1, which setup leaves alone. To run the dev-workflow hooks too, add a line to each of these hooks, creating it if needed, and pass pre-push its stdin:
$(_activate_lines "  $1/")"
      ;;
    *)
      _from="git's $2 config"
      [ "$2" != command ] || _from="git's command line or environment"
      report core.hooksPath conflict "core.hooksPath is $1, from $_from, so git runs the hooks there in this repo too, and setup doesn't set .githooks over it, which would stop them here. To run the dev-workflow hooks as well, add a line to each of these hooks there, creating it if needed, and pass pre-push its stdin. Each line skips a repo that hasn't the hook:
$(_activate_guarded "  $1/")
Or, to run only this repo's own hooks here, set this repo's with: git config core.hooksPath .githooks"
      ;;
  esac
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
  _detected=$(sh "$here/detect.sh" "$1") || return 2
  _git=$(printf '%s\n' "$_detected" | jq -r .git)
  _tool=$(printf '%s\n' "$_detected" | jq -r .hookTool)
  _path=$(printf '%s\n' "$_detected" | jq -r '.hooksPath // ""')
  _scope=$(printf '%s\n' "$_detected" | jq -r '.hooksPathScope // ""')
  _git_hooks=$(printf '%s\n' "$_detected" | jq -r '.gitHooks | join(" ")')

  if [ "$_git" != true ]; then
    report core.hooksPath conflict "not a git repo, so the hooks can't be turned on: run git init, then setup again"
    return 0
  fi
  case $_tool in
    husky) activate_husky "$1" "$2" || return 2 ;;
    lefthook) _activate_lefthook "$1" ;;
    pre-commit | simple-git-hooks)
      _file=.pre-commit-config.yaml
      [ "$_tool" = pre-commit ] || _file=package.json
      report "$_file" conflict "$_tool runs this repo's git hooks, and its settings are the project's: have it run .githooks/pre-commit, .githooks/commit-msg with the message file's path, and .githooks/pre-push with its two arguments and its stdin."
      ;;
    *)
      case $_path in
        "" | .githooks | .githooks/ | "$1/.githooks" | "$1/.githooks/") ;;
        *)
          _activate_other_path "$_path" "$_scope"
          return 0
          ;;
      esac
      if [ -z "$_scope" ] && [ -n "$_git_hooks" ]; then
        move_git_hooks "$1" "$_git_hooks"
        case $? in
          0) ;;
          1) return 0 ;;
          *) return 2 ;;
        esac
      fi
      if [ -f "$1/package.json" ]; then _activate_package "$1" "$2" || return 2; fi
      if [ -n "$_scope" ]; then
        report core.hooksPath keep
      else
        report core.hooksPath update "set to .githooks, which turns the hooks on in this clone"
        step hooks-path
      fi
      ;;
  esac
}
