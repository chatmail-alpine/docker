#!/bin/sh
rundir="/run/chatmail-turn"
realm=$(cat /domain)
exec /temprundir.sh "$rundir" \
  /chatmail-turn --realm "$realm" --socket "$rundir"/turn.socket
