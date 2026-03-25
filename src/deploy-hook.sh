#!/bin/sh

# certbot deploy hook to copy certs and trigger reload

. /tls-watch.lib.sh

set -eu

cert_dir="$RENEWED_LINEAGE"
echo "Running deploy hook for $cert_dir"

cp "$cert_dir/fullchain.pem" "$tls_cert"
cp "$cert_dir/privkey.pem" "$tls_key"
echo "Private key copied to $tls_key"

chown root: "$tls_cert" "$tls_key"
chmod 755 "$tls_cert"
chmod 700 "$tls_key"

echo "Reloading services"
touch "$tls_watch"
