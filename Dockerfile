ARG ALPINE_VER=3.23
ARG RUST_VER=1.93

ARG VMAIL_UID=501
ARG VMAIL_GID=501

# base alpine image for final stages
FROM alpine:$ALPINE_VER AS run-base
ARG VMAIL_UID
ARG VMAIL_GID
RUN addgroup -S -g $VMAIL_GID vmail && \
  adduser -h /home/vmail -s /bin/false -G vmail -S -D -u $VMAIL_UID vmail

# base image to build and run python modules
# (deduplicates `apk add python3` operation)
FROM run-base AS python-base
RUN apk add --no-cache python3

# build chatmaild
FROM python-base AS chatmaild-build
WORKDIR /whl  # create dir for built packages
WORKDIR /src
RUN apk add --no-cache python3-dev py3-pip musl-dev gcc git
RUN git clone \
  --single-branch --depth 1 \
  --revision dbd5cd16f5d8d849120bcac60c139b9bff68374a \
  https://github.com/chatmail/relay.git \
  /src
RUN pip wheel --no-cache-dir -w /whl /src/chatmaild

# base image to run chatmaild
FROM python-base AS chatmaild-base
RUN apk add --no-cache py3-virtualenv && \
  python3 -m venv /venv && \
  apk del py3-virtualenv
WORKDIR /whl
COPY --from=chatmaild-build /whl/*.whl ./
RUN /venv/bin/pip install --no-cache-dir ./*.whl
WORKDIR /
RUN rm -rf /whl
COPY ./src/temprundir.sh /
COPY ./src/chatmaild.sh /
USER $VMAIL_UID:$VMAIL_GID

# run chatmaild services
# ---
FROM chatmaild-base AS metadata-run
# usage: /chatmaild.sh <bin name> <rundir name> <socket filename>
CMD ["/chatmaild.sh", "chatmail-metadata", "chatmail-metadata", "metadata.socket"]

FROM chatmaild-base AS doveauth-run
CMD ["/chatmaild.sh", "doveauth", "doveauth", "doveauth.socket"]

FROM chatmaild-base AS lastlogin-run
CMD ["/chatmaild.sh", "lastlogin", "chatmail-lastlogin", "lastlogin.socket"]
# ---

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
WORKDIR /pkg
COPY \
  --from=dovecot-build \
    /pkg/chatmail/x86_64/dovecot-2.3.*.apk \
    /pkg/chatmail/x86_64/dovecot-lmtpd-2.3.*.apk \
    /pkg/chatmail/x86_64/dovecot-lua-2.3.*.apk \
  ./
RUN apk add --no-cache --allow-untrusted ./*.apk
WORKDIR /
RUN rm -rf /pkg
CMD ["/usr/sbin/dovecot", "-F"]

# build opendkim
FROM abuild-base AS opendkim-build
RUN git clone -b v2.11.0-5 https://git.dc09.xyz/chatmail/opendkim.git /src/opendkim
WORKDIR /src/opendkim
RUN abuild -C chatmail/opendkim -Fr

# run opendkim
FROM run-base AS opendkim-run
WORKDIR /pkg
COPY \
  --from=opendkim-build \
    /pkg/chatmail/x86_64/opendkim-2.11.*.apk \
    /pkg/chatmail/x86_64/opendkim-libs-2.11.*.apk \
    /pkg/chatmail/x86_64/opendkim-utils-2.11.*.apk \
  ./
RUN apk add --no-cache --allow-untrusted ./*.apk
WORKDIR /
RUN rm -rf /pkg
CMD ["/usr/sbin/opendkim", "-u", "opendkim", "-f"]

# temporary base image for rust builds
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
USER 450:450
CMD ["/iroh-relay", "--config-path", "/config.toml"]

# build chatmail-turn
FROM rust-base AS turn-build
WORKDIR /src
RUN git clone -b v0.3 https://github.com/chatmail/chatmail-turn.git /src
RUN cargo build --release

# run chatmail-turn
FROM run-base AS turn-run
COPY ./src/temprundir.sh /
COPY ./src/turn.sh /
COPY --from=turn-build /src/target/release/chatmail-turn /
USER $VMAIL_UID:$VMAIL_GID
EXPOSE 3478/udp
CMD ["/turn.sh"]

# build filtermail
FROM rust-base AS filtermail-build
WORKDIR /src
RUN git clone \
  --revision b982dc5577b44ce1c0ca5bac2106bc944a273eda \
  https://git.dc09.xyz/chatmail/filtermail.git \
  /src
RUN cargo build --profile dist
ARG VMAIL_UID
ARG VMAIL_GID
RUN echo "vmail:x:$VMAIL_UID:$VMAIL_GID::/:/bin/false" >/etc/min-passwd && \
  echo "vmail:x:$VMAIL_GID:" >/etc/min-group

# base image for filtermail
FROM scratch AS filtermail-base
COPY --from=filtermail-build /src/target/dist/filtermail /
COPY --from=filtermail-build /etc/min-passwd /etc/passwd
COPY --from=filtermail-build /etc/min-group /etc/group
ENV HOST_LISTEN=0.0.0.0 HOST_POSTFIX=postfix
USER $VMAIL_UID:$VMAIL_GID

# run filtermail for outgoing mail
FROM filtermail-base AS filtermail-out-run
CMD ["/filtermail", "/etc/chatmail.ini", "outgoing"]

# run filtermail for incoming mail
FROM filtermail-base AS filtermail-in-run
CMD ["/filtermail", "/etc/chatmail.ini", "incoming"]

# build newemail
FROM rust-base AS newemail-build
WORKDIR /src
RUN git clone -b v1.1.0 https://git.dc09.xyz/chatmail/newemail.git /src
RUN cargo build --release

# run newemail
FROM alpine:$ALPINE_VER AS newemail-run
COPY ./src/temprundir.sh /
COPY --from=newemail-build /src/target/release/newemail /
RUN addgroup -S -g 101 nginx && \
  adduser -s /bin/false -G nginx -S -D -H -u 101 nginx
USER 101:101
CMD ["/tmprundir.sh", "/run/newemail", "/newemail"]
