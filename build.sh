#!/bin/sh

set -e

: "${REPOS:=git.dc09.xyz/chatmail}"
: "${BRANCH:=latest}"

docker_build () {
  local target="$1" imgname="$2"

  tags=""
  for repo in $REPOS; do
    tags="$tags -t $repo/$imgname:$BRANCH"
    if [ -n "$VERSION" ]; then
      tags="$tags -t $repo/$imgname:$VERSION"
    fi
  done

  [ "$PUSH" = 1 ] && push="--push" || push=""

  docker buildx build \
    -f Dockerfile \
    --target "$target" \
    $tags \
    $push \
    .
}

if [ -n "$1" ] && [ -n "$2" ]; then
  docker_build "$1" "$2"
  exit
fi

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
