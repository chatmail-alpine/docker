#!/bin/sh

/filtermail "$@" &
pid=$!

for sig in INT TERM; do
  trap "kill -$sig $pid" "$sig"
done

wait "$pid"
