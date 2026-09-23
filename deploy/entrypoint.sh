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
if [ -n "$DOMAIN" ]; then
    if [ ! -d "$STATE/live/$DOMAIN" ]; then
        echo "[entrypoint] requesting a certificate for $DOMAIN"
        certbot certonly --standalone --non-interactive --agree-tos --email "$ACME_EMAIL" \
            -d "$DOMAIN" --config-dir "$STATE" --work-dir /data/work --logs-dir /data/logs
    fi

    # A renewal loop: certificates last 90 days and nothing else here would notice. A renewed certificate
    # is picked up on the next restart, which is the one manual step this deployment has.
    (
        while :; do
            sleep 12h
            certbot renew --quiet --config-dir "$STATE" --work-dir /data/work --logs-dir /data/logs || true
        done
    ) &

    export ZIX_CERT="$STATE/live/$DOMAIN/fullchain.pem"
    export ZIX_KEY="$STATE/live/$DOMAIN/privkey.pem"
else
    echo "[entrypoint] DOMAIN is not set: serving the bundled development certificate."
    echo "[entrypoint] Browsers need the SPKI pin for it. Set DOMAIN (and ACME_EMAIL) for a certificate"
    echo "[entrypoint] this machine holds itself, which is what removes the flags."
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

    su postgres -c "$pgbin/pg_ctl -D $pgdata -l /data/pg.log -o '-c listen_addresses=127.0.0.1' start" >/dev/null
    for _ in $(seq 1 30); do "$pgbin/pg_isready" -q && break; sleep 0.5; done

    su postgres -c "psql -tAc \"SELECT 1 FROM pg_roles WHERE rolname='zix'\" | grep -q 1" \
        || su postgres -c "psql -c \"CREATE ROLE zix LOGIN SUPERUSER PASSWORD 'zix'\"" >/dev/null
    su postgres -c "psql -tAc \"SELECT 1 FROM pg_database WHERE datname='zix_dev'\" | grep -q 1" \
        || su postgres -c "createdb -O zix zix_dev"
fi

# Fly's name for the address a UDP listener must bind; the server takes a numeric address.
session_ip=${ZIX_SESSION_IP:-0.0.0.0}
if [ "$session_ip" = "fly-global-services" ]; then
    session_ip=$(getent hosts fly-global-services | awk '{print $1; exit}')
    echo "[entrypoint] fly-global-services resolves to $session_ip"
fi

export ZIX_SESSION_IP="$session_ip"

exec /app/zix-demo
