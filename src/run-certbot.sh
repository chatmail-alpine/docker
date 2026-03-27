#!/bin/sh

. /tls-watch.lib.sh

if [ ! -f "$tls_key" ]; then
  mail_domain=$(cat /domain)
  cert_domains="$mail_domain www.$mail_domain mta-sts.$mail_domain $ADD_DOMAINS"

  arg_domains=
  for d in $cert_domains; do
    arg_domains="$arg_domains -d $d"
  done

  webroot="${WEBROOT:-/var/www/certbot}"

  echo "Running certbot certonly..."
  echo "  Domains: $cert_domains"
  echo "  Webroot: $webroot"

  /venv/bin/certbot certonly \
    --webroot -w "$webroot" \
    --deploy-hook /deploy-hook.sh \
    $arg_domains
  exit
fi

mkdir -p /cron
echo "${CRON_EXPR:-2 1 * * *} /venv/bin/certbot renew -q" >/cron/root

echo "Running cron..."
/usr/sbin/crond -f -L /dev/stdout -c /cron &
pid=$!

for sig in INT TERM; do
  trap "kill -$sig $pid" "$sig"
done

wait "$pid"
