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

# Fly's name for the address a UDP listener must bind; the server takes a numeric address.
session_ip=${ZIX_SESSION_IP:-0.0.0.0}
if [ "$session_ip" = "fly-global-services" ]; then
    session_ip=$(getent hosts fly-global-services | awk '{print $1; exit}')
    echo "[entrypoint] fly-global-services resolves to $session_ip"
fi

export ZIX_SESSION_IP="$session_ip"

exec /app/zix-demo
