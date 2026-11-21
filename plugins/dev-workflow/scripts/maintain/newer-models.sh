#!/bin/sh
# Usage: newer-models.sh <<'SETTINGS'
#        <reviewer_command>
#        <model_noncoding_alt>
#        SETTINGS
#
# Maintenance's report of a newer reviewer or second-opinion model: the same lines the
# session-start check prints, from the same code, scripts/lib/gpt-newer.sh. The two
# settings come on stdin, a line each, as the skill gets them. An empty line, or one still
# holding a ${user_config...} placeholder because the setting was never saved, means its
# default. Prints nothing when there's nothing newer, or no Codex.

case $0 in
  */*) scripts_dir=${0%/*}/.. ;;
  *) scripts_dir=.. ;;
esac
command -v jq >/dev/null 2>&1 || {
  echo 'newer-models.sh: missing required tool: jq' >&2
  exit 2
}

IFS= read -r reviewer || reviewer=
IFS= read -r alt || alt=
# shellcheck disable=SC2016 # A literal placeholder.
case $reviewer in *'${user_config.'*) reviewer= ;; esac
# shellcheck disable=SC2016 # A literal placeholder.
case $alt in *'${user_config.'*) alt= ;; esac

# shellcheck source=plugins/dev-workflow/scripts/lib/gpt-newer.sh
. "$scripts_dir/lib/gpt-newer.sh"
gpt_newer "$reviewer" "$alt"
