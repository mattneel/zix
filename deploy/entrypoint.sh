#!/usr/bin/env bash
# Obtain a certificate a browser already trusts, then serve.
#
# Two things happen here that a Fly app usually does not do. The certificate is issued *to this process*
# with certbot's standalone responder, because the service passes port 80 straight through: when the edge
# terminates TLS, QUIC cannot work, and a certificate the edge holds is no use to a QUIC server. And the
# UDP listener binds a numeric address, because Fly requires UDP on `fly-global-services`.
set -euo pipefail

DOMAIN=${DOMAIN:?set DOMAIN to the hostname this app answers on}
ACME_EMAIL=${ACME_EMAIL:?set ACME_EMAIL so the certificate authority can warn you before expiry}
STATE=/data/letsencrypt

if [ ! -d "$STATE/live/$DOMAIN" ]; then
    echo "[entrypoint] requesting a certificate for $DOMAIN"
    certbot certonly --standalone --non-interactive --agree-tos --email "$ACME_EMAIL" \
        -d "$DOMAIN" --config-dir "$STATE" --work-dir /data/work --logs-dir /data/logs
fi

# A renewal loop: certificates last 90 days and nothing else here would notice. A renewed certificate is
# picked up on the next restart, which is the one manual step this deployment has.
(
    while :; do
        sleep 12h
        certbot renew --quiet --config-dir "$STATE" --work-dir /data/work --logs-dir /data/logs || true
    done
) &

# Fly's name for the address a UDP listener must bind; the server takes a numeric address.
session_ip=${ZIX_SESSION_IP:-0.0.0.0}
if [ "$session_ip" = "fly-global-services" ]; then
    session_ip=$(getent hosts fly-global-services | awk '{print $1; exit}')
    echo "[entrypoint] fly-global-services resolves to $session_ip"
fi

export ZIX_SESSION_IP="$session_ip"
export ZIX_CERT="$STATE/live/$DOMAIN/fullchain.pem"
export ZIX_KEY="$STATE/live/$DOMAIN/privkey.pem"

exec /app/zix-demo
