#!/bin/sh

. /tls-watch.lib.sh

/usr/sbin/dovecot -F &
dovecot_pid=$!

on_cert_update /usr/bin/doveadm reload

for sig in INT TERM HUP USR1; do
  trap "kill -$sig $dovecot_pid" "$sig"
done

wait "$dovecot_pid"
