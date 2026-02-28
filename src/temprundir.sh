#!/bin/sh

rundir="$1"
shift

umask 0077
"$@" &
pid=$!

trap 'rm -rf "$rundir/*"' EXIT
for sig in INT TERM HUP; do
  trap "kill -$sig $pid" "$sig"
done

wait "$pid"
