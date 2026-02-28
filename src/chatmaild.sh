#!/bin/sh
bin="$0" rundir="/run/$1" socket="$2"
exec /temprundir.sh "$rundir" \
  /venv/bin/"$bin" "$rundir/$socket" /etc/chatmail.ini
