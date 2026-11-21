#!/bin/sh
# Whether Codex lists a newer GPT model than the reviewer or the second opinion uses, for
# hook-session-start.sh and maintain's newer-models.sh, so the two can't disagree. Source
# this file; don't run it. Needs jq, and scripts_dir set to the plugin's scripts folder.
#
# The reviewer and the second opinion run through Codex, so Codex's own list of models,
# which it caches, says when a newer one is out. That cache isn't a published interface,
# so anything unexpected in it, or no Codex at all, means nothing to say. Only slugs in the
# strict shape that gpt-models.jq allows are ever printed.
#
# shellcheck disable=SC2154 # The caller sets scripts_dir.

# Sets model_in_use to the value of -m or --model in a command, or to nothing.
read_model_flag() {
  model_in_use=
  rm_noglob=
  case $- in *f*) rm_noglob=1 ;; esac
  set -f
  # shellcheck disable=SC2086 # Split into words, as the command would be.
  set -- $1
  [ -n "$rm_noglob" ] || set +f
  while [ "$#" -gt 0 ]; do
    case $1 in
      -m | --model)
        [ "$#" -gt 1 ] && model_in_use=$2
        return 0
        ;;
      -m=* | --model=*)
        model_in_use=${1#*=}
        return 0
        ;;
    esac
    shift
  done
}

# gpt_newer <reviewer command> <second-opinion model>: prints a line for each that has a
# newer model in its family, saying which setting to change. Either empty means its
# default in plugin.json.
gpt_newer() {
  gm_cache=${CODEX_HOME:-$HOME/.codex}/models_cache.json
  [ -f "$gm_cache" ] && [ -r "$gm_cache" ] || return 0
  [ -r "$scripts_dir/lib/gpt-models.jq" ] || return 0

  gm_reviewer=$1
  gm_alt=$2
  gm_manifest=$scripts_dir/../.claude-plugin/plugin.json
  [ -n "$gm_reviewer" ] ||
    gm_reviewer=$(jq -r '.userConfig.reviewer_command.default | strings' "$gm_manifest" 2>/dev/null)
  [ -n "$gm_alt" ] ||
    gm_alt=$(jq -r '.userConfig.model_noncoding_alt.default | strings' "$gm_manifest" 2>/dev/null)
  read_model_flag "$gm_reviewer"

  gm_newer=$(jq -rs -L "$scripts_dir/lib" --arg reviewer "$model_in_use" --arg alt "$gm_alt" '
    include "gpt-models";
    select(length == 1 and (.[0] | type == "object")) | .[0]
    | (newer_than($reviewer) | "reviewer \(.) \($reviewer)"),
      (newer_than($alt) | "alt \(.) \($alt)")' "$gm_cache" 2>/dev/null) || return 0

  printf '%s\n' "$gm_newer" | while read -r gm_role gm_slug gm_current gm_extra; do
    # What gpt-models.jq lets through, checked again before it's printed.
    case $gm_slug$gm_current in *[!a-z0-9.-]*) continue ;; esac
    case $gm_slug in gpt-*) ;; *) continue ;; esac
    case $gm_current in gpt-*) ;; *) continue ;; esac
    [ -z "$gm_extra" ] || continue
    case $gm_role in
      reviewer) echo "$gm_slug is available; the reviewer uses $gm_current. Change reviewer_command and reviewer_name in /config." ;;
      alt) echo "$gm_slug is available; the second-opinion model uses $gm_current. Change model_noncoding_alt in /config." ;;
    esac
  done
}
