#!/bin/sh

docker_build () {
  local target="$1" imgname="$2"
  docker buildx build \
    -f Dockerfile \
    --target "$target" \
    -t git.dc09.xyz/chatmail/"$imgname":latest \
    .
}

docker_build metadata-run metadata
docker_build doveauth-run doveauth
docker_build lastlogin-run lastlogin
docker_build cron-run cron
docker_build generate-run generate

docker_build certbot-run certbot
docker_build nginx-run nginx
docker_build postfix-run postfix

docker_build dovecot-run dovecot
docker_build opendkim-run opendkim

docker_build iroh-run iroh-relay
docker_build turn-run turn
docker_build filtermail-run filtermail
docker_build newemail-run newemail
