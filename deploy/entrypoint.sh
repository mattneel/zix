#!/usr/bin/env bash
# Obtain a certificate a browser already trusts, then serve.
#
# Two things happen here that a Fly app usually does not do. The certificate is issued *to this process*
# with certbot's standalone responder, because the service passes port 80 straight through: when the edge
# terminates TLS, QUIC cannot work, and a certificate the edge holds is no use to a QUIC server. And the
# UDP listener binds a numeric address, because Fly requires UDP on `fly-global-services`.
set -euo pipefail

DOMAIN=${DOMAIN:-}
ACME_EMAIL=${ACME_EMAIL:-}
STATE=/data/letsencrypt

# With a DOMAIN, this machine holds a certificate a browser already trusts, which is the whole point: the
# QUIC handshake ends here, so the private key has to be here. Without one, the bundled development
# certificate is served instead and browsers need the SPKI pin - the machine still runs, which is what makes
# a staged deployment possible.
acme_ok=yes
if [ -n "$DOMAIN" ]; then
    # A certificate that cannot be obtained must not take the machine with it: a deployment that serves the
    # self-signed certificate and says so is diagnosable, and one that crash-loops cannot even be shelled
    # into to find out why.
    echo "[entrypoint] acme client: $(command -v lego || echo missing) $(lego --version 2>/dev/null | head -1)"
    if [ ! -d "$STATE/certificates/$DOMAIN" ]; then
        echo "[entrypoint] requesting a certificate for $DOMAIN through a DNS-01 challenge"
        if ! lego --email "$ACME_EMAIL" --dns spaceship --domains "$DOMAIN" --path "$STATE" --accept-tos run; then
            echo "[entrypoint] WARNING: the certificate request failed; serving the development certificate"
            acme_ok=no
        fi
    fi

    if [ "$acme_ok" = no ]; then
        DOMAIN=""
    fi

    # A renewal loop: certificates last 90 days and nothing else here would notice. A renewed certificate
    # is picked up on the next restart, which is the one manual step this deployment has.
    (
        while :; do
            sleep 12h
            lego --email "$ACME_EMAIL" --dns spaceship --domains "$DOMAIN" --path "$STATE" --accept-tos renew --days 30 || true
        done
    ) &

    # The server reads one certificate and a SEC1 key. lego writes the leaf chain and a PKCS#8 key, so the
    # leaf is taken out of the chain and the key converted - the same form the bundled certificate uses.
    openssl x509 -in "$STATE/certificates/$DOMAIN.crt" -out "$STATE/serving-cert.pem"
    openssl ec -in "$STATE/certificates/$DOMAIN.key" -out "$STATE/serving-key.pem" >/dev/null 2>&1 \
        || cp "$STATE/certificates/$DOMAIN.key" "$STATE/serving-key.pem"

    export ZIX_CERT="$STATE/serving-cert.pem"
    export ZIX_KEY="$STATE/serving-key.pem"
else
    # No domain, so no certificate authority will issue for this name. Mint one for the app's own hostname
    # instead: still self-signed, so a browser needs the pin, but its SAN matches the Host a browser sends -
    # and zix answers 421 Misdirected Request for a Host its certificate does not cover, so a certificate
    # that only names localhost cannot serve this deployment at all. Kept on the volume so the pin is stable
    # across deploys.
    app_host=${FLY_APP_NAME:-localhost}.fly.dev
    STATE=/data/selftest

    if [ ! -f "$STATE/cert.pem" ]; then
        echo "[entrypoint] minting a certificate for $app_host"
        mkdir -p "$STATE"
        # ecparam emits a SEC1 key on purpose: `openssl req -newkey ec` writes PKCS#8, and the server's PEM
        # reader expects SEC1, so it fails with ZixInvalidKey on a key openssl considers perfectly fine.
        openssl ecparam -name prime256v1 -genkey -noout -out "$STATE/key.pem"
        openssl req -x509 -new -key "$STATE/key.pem" -out "$STATE/cert.pem" -days 3650 \
            -subj "/O=zix demo/CN=$app_host" -addext "subjectAltName=DNS:$app_host" >/dev/null 2>&1
    elif head -1 "$STATE/key.pem" | grep -q "BEGIN PRIVATE KEY"; then
        # A key minted before that distinction was known: convert it rather than leave a machine that cannot
        # start until someone deletes the volume.
        echo "[entrypoint] converting a PKCS#8 key on the volume to SEC1"
        openssl ec -in "$STATE/key.pem" -out "$STATE/key.sec1.pem" >/dev/null 2>&1 \
            && mv "$STATE/key.sec1.pem" "$STATE/key.pem"
    fi

    export ZIX_CERT="$STATE/cert.pem"
    export ZIX_KEY="$STATE/key.pem"

    spki=$(openssl x509 -in "$STATE/cert.pem" -pubkey -noout | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | openssl base64)
    echo "[entrypoint] certificate for $app_host, self-signed. To open the page, launch a browser with:"
    echo "[entrypoint]   --ignore-certificate-errors-spki-list=$spki --origin-to-force-quic-on=$app_host:443"
fi

# A database in this machine. The demo truncates and seeds its own fixtures at startup, so nothing here
# needs to survive a restart - and keeping it local is what lets the durable slice run without a hosted
# database's TLS requirements. Export DATABASE_URL to use one instead; postgrez does TLS, but its
# ClientHello sends no SNI and offers no RSA signature schemes, so a hosted server that routes by SNI is
# not reachable from it yet.
if [ -z "${DATABASE_URL:-}" ]; then
    export DATABASE_URL="postgres://zix:zix@127.0.0.1:5432/zix_dev"
    pgbin=$(ls -d /usr/lib/postgresql/*/bin | head -1)
    pgdata=/data/pg

    if [ ! -d "$pgdata" ]; then
        echo "[entrypoint] initialising a local database in $pgdata"
        install -d -o postgres -g postgres "$pgdata"
        su postgres -c "$pgbin/initdb -D $pgdata" >/dev/null
    fi

    # The log lives inside PGDATA, which postgres owns: the volume is mounted root-owned, so a log path at
    # the volume root is one the server cannot create.
    su postgres -c "$pgbin/pg_ctl -D $pgdata -l $pgdata/server.log -o '-c listen_addresses=127.0.0.1' start" >/dev/null \
        || { echo "[entrypoint] the local database would not start:"; tail -20 "$pgdata/server.log"; exit 1; }
    for _ in $(seq 1 30); do "$pgbin/pg_isready" -q && break; sleep 0.5; done

    su postgres -c "psql -tAc \"SELECT 1 FROM pg_roles WHERE rolname='zix'\" | grep -q 1" \
        || su postgres -c "psql -c \"CREATE ROLE zix LOGIN SUPERUSER PASSWORD 'zix'\"" >/dev/null
    su postgres -c "psql -tAc \"SELECT 1 FROM pg_database WHERE datname='zix_dev'\" | grep -q 1" \
        || su postgres -c "createdb -O zix zix_dev"
fi

# Fly's name for the address a UDP listener must bind; the server takes a numeric address.
# Default to Fly's own name for it: on this platform a UDP listener has to bind that address, and a wildcard
# bind is not the same thing.
session_ip=${ZIX_SESSION_IP:-fly-global-services}
if [ "$session_ip" = "fly-global-services" ]; then
    session_ip=$(getent hosts fly-global-services | awk '{print $1; exit}')
    echo "[entrypoint] fly-global-services resolves to $session_ip"
fi

export ZIX_SESSION_IP="$session_ip"

exec /app/zix-demo
