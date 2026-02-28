#!/bin/sh
rundir="/run/chatmail-turn"
exec /temprundir.sh "$rundir" \
  /chatmail-turn --realm "$realm" --socket "$rundir"/turn.socket
