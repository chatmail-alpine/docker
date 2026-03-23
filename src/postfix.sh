#!/bin/sh

. /tls-watch.lib.sh

/usr/sbin/postfix start-fg &
postfix_pid=$!

on_cert_update /usr/sbin/postfix reload

for sig in INT TERM HUP; do
  trap "kill -$sig $postfix_pid" "$sig"
done

wait "$postfix_pid"
