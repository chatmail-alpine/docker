#!/bin/sh
rundir="/run/chatmail-turn"
exec /temprundir.sh "$rundir" \
  /chatmail-turn --realm "$REALM" --socket "$rundir"/turn.socket
