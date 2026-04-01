tls_cert=$(head -n 1 /tls/path)
tls_key=$(tail -n 1 /tls/path)
tls_watch="/tls/reload"

watch_pid=

if [ ! -e "$tls_watch" ]; then
  touch "$tls_watch"
fi

on_cert_update () {
  local reload_cmd="$@" dest="/reload.sh"
  echo "#!/bin/sh" >"$dest"
  echo "$reload_cmd" >>"$dest"
  /bin/chmod +x "$dest"

  /sbin/inotifyd "$dest" "$tls_watch":e &
  watch_pid=$!

  trap "kill -INT $watch_pid" EXIT
}
