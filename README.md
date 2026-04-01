# chatmail in docker

This guide will help you to setup a chatmail relay
using only a couple of docker compose commands.

For general info about the purpose and architecture of chatmail relays, please see
[this documentation](https://git.dc09.xyz/chatmail/docs/src/branch/main/index.md#general-info-about-chatmail-relay)
(mirrors: [Codeberg](https://codeberg.org/chatmail-alpine/docs/src/branch/main/index.md#general-info-about-chatmail-relay),
[GitHub](https://github.com/chatmail-alpine/docs/blob/main/index.md#general-info-about-chatmailrelay)).

## Requirements

* Public IP address with non-restricted SMTP and IMAP ports
* Registered domain name
* 1 GB of RAM
* 1 CPU core
* ~10 GB of storage for ~a hundred active users
* Docker Compose installed

## Setup

### Initial DNS

Please set the following DNS records, assuming
`chat.example.com` is your domain and
`1.2.3.4` is your IP (replace them correspondingly):
```dns
chat.example.com.          A      1.2.3.4

www.chat.example.com.      CNAME  chat.example.com
mta-sts.chat.example.com.  CNAME  chat.example.com
```

### Configuration files

For convenience, let's create a separate directory:
```shell
cd
mkdir chatmail
cd chatmail
```

Download compose.yml and example chatmail.ini:
```shell
curl -fsSO https://git.dc09.xyz/chatmail/docker/raw/branch/main/compose.yml
curl -fsS -o chatmail.ini https://git.dc09.xyz/chatmail/docker/raw/branch/main/chatmail.example.ini
```

Alternatively, from mirrors:

<details>
<summary>Mirrors</summary>

**Codeberg**
```shell
curl -fsSO https://codeberg.org/chatmail-alpine/docker/raw/branch/main/compose.yml
curl -fsS -o chatmail.ini https://codeberg.org/chatmail-alpine/docker/raw/branch/main/chatmail.example.ini
```

**GitHub**
```shell
curl -fsSO https://github.com/chatmail-alpine/docker/raw/refs/heads/main/compose.yml
curl -fsS -o chatmail.ini https://github.com/chatmail-alpine/docker/raw/refs/heads/main/chatmail.example.ini
```

</details>

Open chatmail.ini and adjust parameters.
You need to change `mail_domain` to your domain, other options can be left at their defaults.

### Getting certs

First, launch nginx only:
```shell
docker compose up -d nginx
```

Next, run certbot:
```shell
docker compose run --rm certbot
```
Answer a couple of question, and that's it,
you received new TLS certificates for your chatmail.

### Start chatmail

```shell
docker compose up -d
```

Check logs, you shouldn't see any errors:
```shell
docker compose logs
```

### Finish DNS setup

```dns
chat.example.com.  MX  10  chat.example.com.
```
(`10` is a mail server priority)

```dns
_mta-sts.chat.example.com.  TXT  "v=STSv1; id=202604012111"

chat.example.com.           TXT  "v=spf1 a ~all"
_dmarc.chat.example.com.    TXT  "v=DMARC1;p=reject;adkim=s;aspf=s"

_adsp._domainkey.chat.example.com.  TXT  "dkim=discardable"
```

#### DKIM

Read a newly generated public DKIM key:
```shell
docker compose exec opendkim cat /etc/dkimkeys/opendkim.txt
```

You'll get something like:
```text
opendkim._domainkey	IN	TXT	( "v=DKIM1; h=sha256; k=rsa; "
  "p=MIIBIj....uMRk"
  "r6WwhL....QAB" )  ; ----- DKIM key opendkim for chat.example.com
```

Copy the whole `p=` parameter value (it's split in two lines)
and create a DNS record like this, pasting your `p=` value instead:
```dns
opendkim._domainkey.chat.example.com.  TXT  "v=DKIM1;k=rsa;p=MIIBIj...uMRkr6WwhL...QAB;s=email;t=s"
```
(also note the `;s=email;t=s` in the end)

#### SRV

```dns
_submission._tcp.chat.example.com.   SRV  0  1  587  chat.example.com.
_submissions._tcp.chat.example.com.  SRV  0  1  465  chat.example.com.

_imap._tcp.chat.example.com.         SRV  0  1  143  chat.example.com.
_imaps._tcp.chat.example.com.        SRV  0  1  993  chat.example.com.
```
(`0` is priority, `1` is weight, the third number is port)
