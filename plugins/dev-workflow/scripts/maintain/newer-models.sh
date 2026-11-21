#!/bin/sh
# Usage: newer-models.sh <<'SETTINGS'
#        <model_noncoding_alt>
#        <reviewer_command, which can run over more than one line>
#        SETTINGS
#
# Maintenance's report of a newer reviewer or second-opinion model: the same lines the
# session-start check prints, from the same code, scripts/lib/gpt-newer.sh. The two
# settings come on stdin as the skill gets them: the model on the first line, and the
# command on the rest, so a command split over lines stays one. An empty setting, or one
# still holding a ${user_config...} placeholder because it was never saved, means its
# default. Prints nothing when there's nothing newer, or no Codex.

case $0 in
  */*) scripts_dir=${0%/*}/.. ;;
  *) scripts_dir=.. ;;
esac
command -v jq >/dev/null 2>&1 || {
  echo 'newer-models.sh: missing required tool: jq' >&2
  exit 2
}

IFS= read -r alt || alt=
reviewer=$(cat)
# shellcheck disable=SC2016 # A literal placeholder.
case $reviewer in *'${user_config.'*) reviewer= ;; esac
# shellcheck disable=SC2016 # A literal placeholder.
case $alt in *'${user_config.'*) alt= ;; esac

# shellcheck source=plugins/dev-workflow/scripts/lib/gpt-newer.sh
. "$scripts_dir/lib/gpt-newer.sh"
gpt_newer "$reviewer" "$alt"
