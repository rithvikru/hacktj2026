#!/usr/bin/env bash

set -euo pipefail

PORT="${PORT:-8000}"

for iface in en0 en1; do
  if ipconfig getifaddr "$iface" >/dev/null 2>&1; then
    IP="$(ipconfig getifaddr "$iface")"
    echo "http://${IP}:${PORT}"
    exit 0
  fi
done

echo "Unable to detect LAN IP on en0/en1" >&2
exit 1
