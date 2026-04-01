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

Create a directory where chatmail relay stores all of its files:
```shell
mkdir instance
```

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

(Important) Restart nginx so it will run with a different config with TLS enabled:
```shell
docker compose restart nginx
```

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

## Special cases

Basically, you can modify your compose.yml whatever the way you want
if you know what you're doing.

But properly configuring TLS certs can be a bit tricky,
here's how to do it when you want to manage certs from the outside.

### I already have certbot installed

Note: it may be better to issue certs for chatmail separately.
Please check if the second option "I&nbsp;already have nginx installed" suits your case.

First, run the generator script to initialize the directory tree:
```shell
docker compose run --rm generate
```

You have to add a deploy hook that your ACME client will run on every cert renewal
to copy certs and reload chatmail services.
For certbot, this can be done by creating and `chmod +x`ing the following script
in `/etc/letsencrypt/renewal-hooks/deploy/chatmail.sh`:

<details>
<summary>Script contents</summary>

```shell
#!/bin/sh

set -eu

cert_dir="$RENEWED_LINEAGE"
# or simply:
#cert_dir="/etc/letsencrypt/live/chat.example.com"

# replace to your instance directory!
target_dir="/home/user/chatmail/instance/config/tls"

tls_cert="$target_dir/cert.pem"
tls_key="$target_dir/key.pem"

echo "Running deploy hook for $cert_dir"

cp "$cert_dir/fullchain.pem" "$tls_cert"
cp "$cert_dir/privkey.pem" "$tls_key"
echo "Private key copied to $tls_key"

chown root: "$tls_cert" "$tls_key"
chmod 644 "$tls_cert"
chmod 600 "$tls_key"

echo "Reloading services"
touch "$target_dir/reload"
```

</details>

Run this deploy hook once to initially copy your certs to the required path:
```shell
RENEWED_LINEAGE="/etc/letsencrypt/live/chat.example.com" \
  /etc/letsencrypt/renewal-hooks/deploy/chatmail.sh
```

Now, comment out or remove the `certbot:` block from your compose.yml.

Restart nginx from chatmail compose if you started it before
and proceed to the next steps.

### I already have nginx installed

**See the [provided nginx config](https://git.dc09.xyz/chatmail/docker/src/branch/main/src/config/nginx/nginx.conf.j2)
as a reference**
(mirrors: [Codeberg](https://codeberg.org/chatmail-alpine/docker/src/branch/main/src/config/nginx/nginx.conf.j2),
[GitHub](https://github.com/chatmail-alpine/docker/blob/main/src/config/nginx/nginx.conf.j2)).

Comment out or remove the `nginx:` block from your compose.yml.

#### web pages
Configure nginx to serve static files on `chat.example.com`, `mta-sts.chat.example.com`
and `www.chat.example.com` from the webroot directory `/home/user/chatmail/instance/web`
(assuming `/home/user/chatmail` is where you put the compose + ini configs
and the instance directory).

#### newemail and iroh
Uncomment the `ports:` block for `iroh-relay` service in compose.yml
to access iroh from your nginx on the host.

Reverse proxy these paths on `chat.example.com`:

<details>
<summary>nginx config snippet</summary>

```nginx
location /new {
  if ($request_method = GET) {
    return 301 dcaccount:https://chat.example.com/new;
  }
  proxy_pass http://unix:/home/user/chatmail/instance/socket/newemail/actix.sock;
  proxy_http_version 1.1;
}

location /relay {
  proxy_pass http://127.0.0.1:3340;
  proxy_http_version 1.1;
  proxy_set_header Connection "upgrade";
  proxy_set_header Upgrade $http_upgrade;
}

location /relay/probe {
  proxy_pass http://127.0.0.1:3340;
  proxy_http_version 1.1;
}

location /generate_204 {
  proxy_pass http://127.0.0.1:3340;
  proxy_http_version 1.1;
}
```

</details>

#### certbot
If you use the chatmail-provided certbot, i.&nbsp;e. didn't follow the instructions above
to replace it with your own ACME client and decided to issue certs for chatmail separately,
you also need to configure your HTTP server to serve static files for the same hosts
from the certbot webroot directory `/home/user/chatmail/instance/data/certbot/web`
in case a path under `/.well-known/acme-challenge/` is requested.

Note: the certbot webroot contains a `.well-known` directory,
i.&nbsp;e. you have to set `root`, not an `alias`
(alternatively, `rewrite` + `alias`, but why would you need such a complexity).

TLS certificate issued by the chatmail certbot is located in
`/home/user/chatmail/instance/config/tls/cert.pem` and `key.pem`.

#### mail on port 443
Chatmail multiplexes https and smtps/imaps on the same port
so relays remain accessible even when ports other than 443 are blocked
on the client's side.

To do so, move all your virtual hosts (`server{}`s) to a local listen port or a unix socket,
like this:

<details>
<summary>nginx config snippet</summary>

```nginx
# Before
http {
  server {
    listen 443 ssl;
    server_name example.com;
    root /var/www/pages;
  }
}

# After
http {
  server {
    listen unix:/run/nginx/nginx.sock ssl;
    # or
    #listen 127.0.0.1:8443 ssl;
    server_name example.com;
    root /var/www/pages;
  }
}
```

</details>

...and then create a `stream` server proxying connections based on matched ALPN:

<details>
<summary>nginx config snippet</summary>

```nginx
stream {
  map $ssl_preread_alpn_protocols $proxy {
    default unix:/run/nginx/nginx.sock;
    # or, if you chose to use a local port instead
    #default 127.0.0.1:8443;
    ~\bsmtp\b 127.0.0.1:465;
    ~\bimap\b 127.0.0.1:993;
  }

  server {
    listen 443;
    listen [::]:443;
    ssl_preread on;
    proxy_pass $proxy;
  }
}
```

</details>

Alternatively, if you *really* don't want to modify `listen` directives in your nginx config,
you may (but shouldn't) remove the support for 443 multiplexing.
Open `src/web/.well-known/autoconfig/mail/config-v1.1.xml` and delete one incomingServer
and one outgoingServer blocks where port is set to 443.
