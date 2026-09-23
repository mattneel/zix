#!/usr/bin/env bash
# lego's exec DNS provider: it calls this with `present` or `cleanup` and exports the challenge record in
# EXEC_FQDN / EXEC_VALUE. The Spaceship API replaces a zone on write, so the hook reads the records, changes
# the one it owns, and writes the set back - which is also why cleanup removes only the record it added.
set -euo pipefail

zone=${ACME_ZONE:?set ACME_ZONE to the zone the challenge record belongs in}
action=${1:?expected `present` or `cleanup`}

: "${SPACESHIP_API_KEY:?}"; : "${SPACESHIP_API_SECRET:?}"
base=${SPACESHIP_API_BASE:-https://spaceship.dev/api}
url="$base/v1/dns/records/$zone"
auth=(-H "X-API-Key: $SPACESHIP_API_KEY" -H "X-API-Secret: $SPACESHIP_API_SECRET" -H 'Content-Type: application/json')

# EXEC_FQDN is the challenge name; the API wants it relative to the zone.
name=${EXEC_FQDN%.$zone}

current=$(mktemp); next=$(mktemp)
trap 'rm -f "$current" "$next"' EXIT
curl -sS --fail-with-body "$url?take=500&skip=0" "${auth[@]}" | jq -c '.items' > "$current"

case "$action" in
  present)
    jq -c --arg n "$name" --arg v "$EXEC_VALUE" \
      '{items: (. + [{"type":"TXT","name":$n,"value":$v,"ttl":60}])}' "$current" > "$next"
    ;;
  cleanup)
    jq -c --arg n "$name" --arg v "$EXEC_VALUE" \
      '{items: map(select((.name == $n and .value == $v) | not))}' "$current" > "$next"
    ;;
  *) echo "unknown action: $action" >&2; exit 2 ;;
esac

curl -sS --fail-with-body -X PUT -H 'Content-Type: application/json' "${auth[@]}" \
  --data-binary "@$next" "$url" > /dev/null
echo "acme-dns-hook: $action $EXEC_FQDN"
