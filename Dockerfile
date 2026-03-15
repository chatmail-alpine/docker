ARG ALPINE_VER=3.23
ARG RUST_VER=1.93

# base alpine image for final stages
FROM alpine:$ALPINE_VER AS run-base
RUN <<EOF
  add_ug () {
    local uid="$1" gid="$2" name="$3" homedir="$4"
    addgroup -S -g "$gid" "$name"
    adduser -SDH -h "$homedir" -s /bin/false -G "$name" -u "$uid" "$name"
  }
  add_ug 101 101 nginx /var/lib/nginx
  add_ug 201 201 postfix /var/spool/postfix
  add_ug 202 202 opendkim /run/opendkim
  add_ug 501 501 vmail /home/vmail
EOF


# -----
# chatmaild images start

# base image to build and run python modules
# (deduplicates `apk add python3` operation)
FROM run-base AS python-base
RUN apk add --no-cache python3

# build chatmaild
FROM python-base AS chatmaild-build
WORKDIR /src
RUN apk add --no-cache py3-virtualenv python3-dev musl-dev gcc git
RUN python3 -m venv /venv
RUN git clone \
  --single-branch --depth 1 \
  --revision ff541b81ea35f403ad960604dd4fc8b5427f64ba \
  https://github.com/chatmail/relay.git \
  /src
RUN /venv/bin/pip install --no-cache-dir /src/chatmaild

# base image to run chatmaild
FROM python-base AS chatmaild-base
COPY --from=chatmaild-build /venv /venv
COPY ./src/temprundir.sh ./src/chatmaild.sh /
USER vmail:vmail

# ---
# run chatmaild services
FROM chatmaild-base AS metadata-run
# usage: /chatmaild.sh <bin name> <rundir name> <socket filename>
CMD ["/chatmaild.sh", "chatmail-metadata", "chatmail-metadata", "metadata.socket"]

FROM chatmaild-base AS doveauth-run
CMD ["/chatmaild.sh", "doveauth", "doveauth", "doveauth.socket"]

FROM chatmaild-base AS lastlogin-run
CMD ["/chatmaild.sh", "lastlogin", "chatmail-lastlogin", "lastlogin.socket"]
# ---

# run chatmail-expire and fsreport
FROM chatmaild-base AS cron-run
WORKDIR /cron
COPY ./src/crontab /cron/vmail
USER root:root  # required for crond
CMD ["/usr/sbin/crond", "-f", "-L", "/dev/stdout", "-c", "/cron"]

# update virtualenv for config generator
FROM chatmaild-build AS generate-build
RUN --mount=type=bind,source=./src/generate/requirements.txt,target=/req.txt \
  /venv/bin/pip install --no-cache-dir -r /req.txt

# run config+webpages generator
FROM python-base AS generate-run
COPY --from=generate-build /venv /venv
COPY ./src/generate/main.py /
CMD ["/venv/bin/python3", "/main.py"]

# chatmaild images end
# -----


# run postfix
FROM run-base AS postfix-run
RUN apk add --no-cache postfix
EXPOSE 25 465 587
CMD ["/usr/sbin/postfix", "start-fg"]


# -----
# custom abuilds start (dovecot and opendkim)

# temporary image for apk builds
FROM alpine:$ALPINE_VER AS abuild-base
RUN apk update && apk add --no-cache alpine-sdk git
ENV REPODEST=/pkg ABUILD_USERDIR=/abuild SUDO=
RUN abuild-keygen -ain
WORKDIR /src

# build patched dovecot
FROM abuild-base AS dovecot-build
RUN git clone -b v2.3.21.1-3 https://git.dc09.xyz/chatmail/dovecot.git /src/dovecot
WORKDIR /src/dovecot
RUN abuild -C chatmail/dovecot -Fr

# run dovecot
FROM run-base AS dovecot-run
# --allow-untrusted is safe since we build packages locally;
# copying repo keys brings in unnecessary complexity
RUN --mount=type=bind,from=dovecot-build,source=/pkg/chatmail/x86_64,target=/tmp/pkg \
  apk add --no-cache --allow-untrusted \
    /tmp/pkg/dovecot-2.3.*.apk \
    /tmp/pkg/dovecot-lmtpd-2.3.*.apk \
    /tmp/pkg/dovecot-lua-2.3.*.apk
EXPOSE 143 993
CMD ["/usr/sbin/dovecot", "-F"]

# build opendkim
FROM abuild-base AS opendkim-build
RUN git clone -b v2.11.0-5 https://git.dc09.xyz/chatmail/opendkim.git /src/opendkim
WORKDIR /src/opendkim
RUN abuild -C chatmail/opendkim -Fr

# run opendkim
FROM run-base AS opendkim-run
# see note on --allow-untrusted above
RUN --mount=type=bind,from=opendkim-build,source=/pkg/chatmail/x86_64,target=/tmp/pkg \
  apk add --no-cache --allow-untrusted \
    /tmp/pkg/opendkim-2.11.*.apk \
    /tmp/pkg/opendkim-libs-2.11.*.apk \
    /tmp/pkg/opendkim-utils-2.11.*.apk
COPY ./src/opendkim.sh /
CMD ["/opendkim.sh"]

# custom abuilds end
# -----


# -----
# rust chatmail components start

# temporary base image for rust builds
# (deduplicates `apk add git` and rust image tag specifier)
FROM rust:$RUST_VER-alpine AS rust-base
RUN apk add --no-cache git

# build iroh relay
FROM rust-base AS iroh-build
WORKDIR /src
RUN git clone \
  -b v0.35.0 --single-branch --depth 1 \
  https://github.com/n0-computer/iroh.git \
  /src
RUN cargo build --package iroh-relay --features server --profile optimized-release
RUN echo 'iroh:x:450:450::/:/bin/false' >/etc/min-passwd && \
  echo 'iroh:x:450:' >/etc/min-group

# run iroh
FROM scratch AS iroh-run
COPY --from=iroh-build /src/target/optimized-release/iroh-relay /
COPY --from=iroh-build /etc/min-passwd /etc/passwd
COPY --from=iroh-build /etc/min-group /etc/group
COPY ./src/iroh-relay.toml /config.toml
USER 450:450
CMD ["/iroh-relay", "--config-path", "/config.toml"]

# build chatmail-turn
FROM rust-base AS turn-build
WORKDIR /src
RUN git clone -b v0.3 https://github.com/chatmail/chatmail-turn.git /src
RUN cargo build --release

# run chatmail-turn
FROM run-base AS turn-run
COPY --from=turn-build /src/target/release/chatmail-turn /
COPY ./src/temprundir.sh ./src/turn.sh /
USER vmail:vmail
EXPOSE 3478/udp
CMD ["/turn.sh"]

# build filtermail
FROM rust-base AS filtermail-build
WORKDIR /src
RUN git clone \
  --revision 977af0152234691bc267071a2737e5625d8b9577 \
  https://github.com/chatmail/filtermail.git \
  /src
RUN cargo build --release

# run filtermail
FROM run-base AS filtermail-run
COPY --from=filtermail-build /src/target/release/filtermail /
USER vmail:vmail
ENTRYPOINT ["/filtermail", "/etc/chatmail.ini"]

# build newemail
FROM rust-base AS newemail-build
WORKDIR /src
RUN git clone -b v1.1.0 https://git.dc09.xyz/chatmail/newemail.git /src
RUN cargo build --release

# run newemail
FROM run-base AS newemail-run
COPY --from=newemail-build /src/target/release/newemail /
COPY ./src/temprundir.sh /
USER nginx:nginx
CMD ["/temprundir.sh", "/run/newemail", "/newemail"]

# rust chatmail components end
# -----
