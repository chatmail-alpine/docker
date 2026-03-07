#!/bin/sh

get_cfg_field () {
  grep "^$1 " /etc/opendkim/opendkim.conf | head -n 1 | awk '{print $2}'
}

key_file=$(get_cfg_field KeyFile)
# generate new key if does not exist
if [ -n "$key_file" ] && [ ! -f "$key_file" ]; then
  domain=$(get_cfg_field Domain)
  selector=$(get_cfg_field Selector)
  /usr/bin/opendkim-genkey -D /etc/dkimkeys -d "$domain" -s "$selector"
  chown -R opendkim: /etc/dkimkeys
  echo "Created new key '$key_file' for domain '$domain'"
fi

exec /usr/sbin/opendkim -u opendkim -f
