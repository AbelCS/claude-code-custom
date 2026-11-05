#!/bin/sh
# Runs the data-access tests in tests/db against a Postgres of their own in Docker: one
# container named dwtest-litestar-postgres-<random>, its data in memory, on a port Docker
# picks, so it never meets another database. It starts nothing if Docker isn't running or
# the name is taken, and removes that container, by the ID Docker gave it, when it's done.

cd "$(dirname "$0")/.." || exit 1

IMAGE=postgres:18.6

fail() {
  printf 'db-test: %s\n' "$*" >&2
  exit 1
}

docker info >/dev/null 2>&1 || fail "Docker isn't running: start it, then run this again"

name=dwtest-litestar-postgres-$(od -An -N4 -tx4 /dev/urandom | tr -d ' \n')
case $name in
  dwtest-litestar-postgres-?*) ;;
  *) fail "could not make a container name" ;;
esac
taken=$(docker ps -aq --filter "name=^/$name\$") || fail "could not list Docker's containers"
[ -z "$taken" ] || fail "a container called $name is already there, so nothing was started"

# Only the container this run started, by its ID, and only if it still has its name.
id=
cleanup() {
  [ -n "$id" ] || return 0
  [ "$(docker inspect --format '{{.Name}}' "$id" 2>/dev/null)" = "/$name" ] || return 0
  echo "db-test: removing container $name" >&2
  docker rm -f -v "$id" >/dev/null || {
    echo "db-test: could not remove $name" >&2
    return 1
  }
  id=
}
trap 'cleanup; exit 129' HUP
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

run() {
  id=$(docker run -d --name "$name" --label dwtest.fixture=litestar-postgres \
    -e POSTGRES_PASSWORD=dwtest -e POSTGRES_DB=notes \
    --tmpfs /var/lib/postgresql -p 127.0.0.1::5432 "$IMAGE") || {
    # It can be made and then fail to start, with no ID printed.
    id=$(docker ps -aq --filter "name=^/$name\$" --filter label=dwtest.fixture=litestar-postgres)
    return 1
  }

  # The image starts a server for its set-up on a socket only, then the real one, which
  # is the first to answer on TCP.
  tries=0
  until docker exec "$name" psql -h 127.0.0.1 -U postgres -d notes -qtAc 'select 1' >/dev/null 2>&1; do
    tries=$((tries + 1))
    [ "$tries" -lt 60 ] || {
      echo "db-test: Postgres didn't start in 60 seconds" >&2
      docker logs "$name" >&2
      return 1
    }
    sleep 1
  done
  port=$(docker port "$name" 5432/tcp | sed -n 's/^127\.0\.0\.1:\([0-9][0-9]*\)$/\1/p' | head -n 1)
  [ -n "$port" ] || {
    echo "db-test: could not find the port Docker gave $name" >&2
    return 1
  }
  DATABASE_URL="postgresql://postgres:dwtest@127.0.0.1:$port/notes" uv run --frozen pytest -q tests/db
}

run
status=$?
cleanup || status=1
exit "$status"
