#!/bin/sh

global_ngx_cfg='daemon off;'

. /tls-watch.lib.sh

if [ ! -f "$tls_key" ]; then
  ngx_cfg="/etc/nginx/nginx.conf.no-tls"
else
  ngx_cfg="/etc/nginx/nginx.conf"
fi

/usr/sbin/nginx -c "$ngx_cfg" -g "$global_ngx_cfg" &
ngx_pid=$!

on_cert_update /usr/sbin/nginx -s reload

for sig in INT TERM HUP QUIT USR1 USR2; do
  trap "kill -$sig $ngx_pid" "$sig"
done

wait "$ngx_pid"
