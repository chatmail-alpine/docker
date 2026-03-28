#!/bin/sh

. /tls-watch.lib.sh

# restore some of alpine-provided configs
for cfg in postfix-files postfix-files.d dynamicmaps.cf dynamicmaps.cf.d; do
  cp -rf /etc/postfix.orig/"$cfg" /etc/postfix
done

/usr/sbin/postfix start-fg &
postfix_pid=$!

on_cert_update /usr/sbin/postfix reload

for sig in INT TERM HUP; do
  trap "kill -$sig $postfix_pid" "$sig"
done

wait "$postfix_pid"
