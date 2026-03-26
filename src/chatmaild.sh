#!/bin/sh
bin="$1" rundir="/run/$2" socket="$3"
exec /temprundir.sh "$rundir" \
  /venv/bin/"$bin" "$rundir/$socket" /etc/chatmail.ini
