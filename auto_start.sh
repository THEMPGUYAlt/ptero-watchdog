#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/.env"

get_servers() {
  curl -s "$PANEL_URL/api/application/servers" \
    -H "Authorization: Bearer $API_KEY" \
    -H "Content-Type: application/json" | jq -r '.data[].attributes.uuid'
}

get_port_for() {
  local uuid="$1"
  curl -s "$PANEL_URL/api/application/servers/$uuid/allocations" \
    -H "Authorization: Bearer $API_KEY" \
    -H "Content-Type: application/json" | jq -r '.data[] | .attributes.port' | head -n1
}

for uuid in $(get_servers); do
  port=$(get_port_for "$uuid")
  if [[ -n "$port" ]]; then
    echo "[MANAGER] Launching watchdog for $uuid on port $port"
    bash "$(dirname "$0")/server-watchdog.sh" "$uuid" "$port" &
  fi
done

wait
