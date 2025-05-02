#!/usr/bin/env bash

set -euo pipefail

: "${SERVERS?SERVERS env variable not exported}"
: "${KEYS_PUB?KEYS_PUB env variable not exported}"

TMP_KEYS=$(mktemp)
trap 'rm -f "$TMP_KEYS"' EXIT

cat "$KEYS_PUB"/*.pub | sort -u > "$TMP_KEYS"
KEY_TOTAL=$(wc -l < "$TMP_KEYS")

echo "🗝️  $KEY_TOTAL unique public keys found"
echo "🔗  ${SERVERS// /, }  —  $(wc -w <<< "$SERVERS") server(s)"

for host in $SERVERS; do
  echo "── $host ─────────────────────────────"
  OLD=$(ssh "$host" 'cat ~/.ssh/authorized_keys 2>/dev/null || true' | sort -u)
  OLD_CNT=$(wc -l <<< "$OLD")

  ssh "$host" 'mkdir -p ~/.ssh && chmod 700 ~/.ssh &&
               [ -f ~/.ssh/authorized_keys ] &&
               cp ~/.ssh/authorized_keys ~/.ssh/authorized_keys.bak.$(date +%s) || true'

  scp -q "$TMP_KEYS" "$host:~/.ssh/authorized_keys"
  ssh "$host" 'chmod 600 ~/.ssh/authorized_keys'

  NEW_CNT=$KEY_TOTAL
  ADDED=$(( NEW_CNT - OLD_CNT > 0 ? NEW_CNT - OLD_CNT : 0 ))
  REMOVED=$(( OLD_CNT - KEY_TOTAL > 0 ? OLD_CNT - KEY_TOTAL : 0 ))

  echo "   before: $OLD_CNT key(s) | after: $NEW_CNT key(s)  (+$ADDED / ‑$REMOVED)"
done

echo -e "\n✅  Synchronisation complete"
