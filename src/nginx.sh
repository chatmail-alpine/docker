#!/bin/sh

global_ngx_cfg='daemon off;'

tls_cert=$(head -n 1 /tls/path)
tls_key=$(tail -n 1 /tls/path)
tls_watch=$(dirname "$tls_key")

if [ ! -f "$tls_key" ]; then
  ngx_cfg="/etc/nginx/nginx.conf.no-tls"
else
  ngx_cfg="/etc/nginx/nginx.conf"
fi

/usr/sbin/nginx -c "$ngx_cfg" -g "$global_ngx_cfg" &
ngx_pid=$!

cat >/reload.sh <<-EOF
  #!/bin/sh
  /usr/sbin/nginx -s reload
EOF
chmod +x reload.sh

/sbin/inotifyd /reload.sh "$tls_watch":e &
watch_pid=$!

trap "kill -INT $watch_pid" EXIT
for sig in INT TERM HUP QUIT USR1 USR2; do
  trap "kill -$sig $ngx_pid" "$sig"
done

wait "$ngx_pid"
