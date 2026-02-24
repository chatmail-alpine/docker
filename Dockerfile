# build chatmaild
FROM python:3.14-alpine AS chatmaild-build
WORKDIR /whl  # create dir for built packages
WORKDIR /src
RUN apk add --no-cache musl-dev gcc git
RUN git clone --single-branch --depth 1 https://github.com/chatmail/relay.git /src
RUN pip wheel --no-cache-dir -w /whl /src/chatmaild

# temporary image for apk builds
FROM alpine:3.23 AS abuild-base
RUN apk update && apk add --no-cache alpine-sdk git
ENV REPODEST=/pkg ABUILD_USERDIR=/abuild SUDO=
RUN abuild-keygen -ain
WORKDIR /src

# build patched dovecot
FROM abuild-base AS dovecot-build
RUN git clone https://git.dc09.xyz/chatmail/dovecot.git /src/dovecot
WORKDIR /src/dovecot
RUN abuild -C chatmail/dovecot -Fr

# build opendkim
FROM abuild-base AS opendkim-build
RUN git clone https://git.dc09.xyz/chatmail/opendkim.git /src/opendkim
WORKDIR /src/opendkim
RUN abuild -C chatmail/opendkim -Fr

# temporary base image for rust builds
FROM rust:1.93-alpine AS rust-base
RUN apk add --no-cache git

# build iroh relay
FROM rust-base AS iroh-build
WORKDIR /src
RUN git clone --single-branch -b v0.35.0 --depth 1 \
  https://github.com/n0-computer/iroh.git /src
RUN cargo build --package iroh-relay --features server --profile optimized-release

# build chatmail-turn
FROM rust-base AS turn-build
WORKDIR /src
RUN git clone https://github.com/chatmail/chatmail-turn.git /src
RUN cargo build --release

# build filtermail
FROM rust-base AS filtermail-build
WORKDIR /src
RUN git clone https://github.com/chatmail/filtermail.git /src
RUN cargo build --profile dist

# build newemail
FROM rust-base AS newemail-build
WORKDIR /src
RUN git clone https://git.dc09.xyz/chatmail/newemail.git /src
RUN cargo build --release
