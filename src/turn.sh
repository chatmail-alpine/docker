#!/bin/sh

get_ini_field () {
  local name="$1"
  local regex="/^\s*$name\s*=/s/^[^=]+=\s*(\"([^\"]*)\"|'([^']*)'|([^#]*))(\s+#.*)?$/\2\3\4/p"
  sed -En "$regex" /etc/chatmail.ini | xargs
}

domain=$(get_ini_field mail_domain)

rundir="/run/chatmail-turn"
exec /temprundir.sh "$rundir" \
  /chatmail-turn --realm "$domain" --socket "$rundir"/turn.socket
