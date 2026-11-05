#!/bin/sh
# Runs the database tests in supabase/tests with pgTAP, against a database of this
# project's own: only Postgres, under the project_id and port in supabase/config.toml.
#
# It starts nothing if Docker isn't running, if the project_id doesn't start with
# dwtest-, or if that project's containers or its port are taken, so it never touches
# another stack. Afterwards it removes exactly what it started, the containers, volumes
# and network labelled with that project_id, after checking each name holds it.

cd "$(dirname "$0")/.." || exit 1

fail() {
  printf 'db-test: %s\n' "$*" >&2
  exit 1
}

project=$(sed -n 's/^project_id = "\(.*\)"$/\1/p' supabase/config.toml)
case $project in
  dwtest-*) ;;
  *) fail "the project_id in supabase/config.toml has to start with dwtest-, not: $project" ;;
esac
port=$(awk '/^\[/ { db = ($0 == "[db]") } db && $1 == "port" { print $3 }' supabase/config.toml)
[ -n "$port" ] || fail "no [db] port in supabase/config.toml"

docker info >/dev/null 2>&1 || fail "Docker isn't running: start it, then run this again"

label=com.supabase.cli.project=$project
# Every container, volume and network with this project's label, one "<kind> <name>" a line.
ours() {
  docker ps -a --filter "label=$label" --format 'container {{.Names}}' &&
    docker volume ls --filter "label=$label" --format 'volume {{.Name}}' &&
    docker network ls --filter "label=$label" --format 'network {{.Name}}'
}

found=$(ours) || fail "could not list Docker's containers, volumes and networks"
[ -z "$found" ] || fail "$project is running or left over from an earlier run, so nothing was started. It holds:
$found
Remove exactly that with: npx supabase stop --no-backup --project-id $project"
if nc -z -w 1 127.0.0.1 "$port" 2>/dev/null; then
  fail "port $port is in use, so nothing was started: set [db] port in supabase/config.toml to a free one"
fi

cleanup() {
  found=$(ours) || {
    echo "db-test: could not list what $project left, so nothing was removed" >&2
    return 1
  }
  [ -n "$found" ] || return 0
  printf 'db-test: removing:\n%s\n' "$found" >&2
  if printf '%s\n' "$found" | awk -v p="$project" '{ n = $2; if (substr(n, length(n) - length(p) + 1) != p || index(n, "dwtest-") == 0) bad = 1 } END { exit bad }'; then
    npx supabase stop --no-backup --project-id "$project" >&2
  else
    echo "db-test: something there doesn't end in $project, so nothing was removed" >&2
    return 1
  fi
  left=$(ours)
  [ -z "$left" ] || {
    printf 'db-test: still there:\n%s\n' "$left" >&2
    return 1
  }
}

trap 'cleanup; exit 129' HUP
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM
npx supabase db start --workdir .
started=$?
if [ "$started" -eq 0 ]; then
  npx supabase test db --workdir .
  status=$?
else
  echo "db-test: the database didn't start" >&2
  status=$started
fi
cleanup || status=1
exit "$status"
