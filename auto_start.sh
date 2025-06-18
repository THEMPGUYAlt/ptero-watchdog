#!/bin/bash

ENV_FILE=".env"
if [[ -f "$ENV_FILE" ]]; then
  export $(grep -v '^#' "$ENV_FILE" | xargs)
else
  echo ".env file missing!"
  exit 1
fi

LOCK_DIR="/tmp/ptero-autostart"
mkdir -p "$LOCK_DIR"

get_all_servers() {
  curl -s -H "Authorization: Bearer $API_KEY" \
    "$PANEL_URL/api/application/servers" |
    jq -c '.data[] | {uuid: .attributes.uuid, id: .attributes.id}'
}

get_status() {
  local sid="$1"
  curl -s -H "Authorization: Bearer $API_KEY" \
    "$PANEL_URL/api/application/servers/$sid/utilization" |
    jq -r '.attributes.state'
}

get_port() {
  local sid="$1"
  curl -s -H "Authorization: Bearer $API_KEY" \
    "$PANEL_URL/api/application/servers/$sid" |
    jq -r '.attributes.allocation.port'
}

start_server() {
  local sid="$1"
  curl -s -X POST -H "Authorization: Bearer $API_KEY" \
    -H "Content-Type: application/json" \
    -d '{"signal":"start"}' \
    "$PANEL_URL/api/application/servers/$sid/power"
}

start_gate() {
  local uuid="$1"
  local port="$2"
  local pid_file="$LOCK_DIR/gate-$uuid.pid"

  if [[ -f "$pid_file" ]]; then return; fi

  gate --port "$port" --message "§aThis server is offline, please wait." &
  echo $! > "$pid_file"
  echo "[GATE $uuid] Started on port $port"
}

stop_gate() {
  local uuid="$1"
  local pid_file="$LOCK_DIR/gate-$uuid.pid"

  if [[ -f "$pid_file" ]]; then
    kill "$(cat "$pid_file")" 2>/dev/null
    rm -f "$pid_file"
    echo "[GATE $uuid] Stopped"
  fi
}

watchdog() {
  local uuid="$1"
  local sid="$2"
  local port="$3"
  local cooldown=${MIN_OFFLINE:-600}
  local lock="$LOCK_DIR/$uuid.lock"
  local last_shutdown=$(date +%s)

  while true; do
    local state
    state=$(get_status "$sid")

    if [[ "$state" == "running" ]]; then
      stop_gate "$uuid"
      while [[ "$(get_status "$sid")" == "running" ]]; do sleep 5; done
      echo "[MC $uuid] Stopped"
      last_shutdown=$(date +%s)

    elif [[ "$state" == "starting" ]]; then
      stop_gate "$uuid"
      echo "[MC $uuid] Starting..."
      sleep 5

    else
      now=$(date +%s)
      delta=$((now - last_shutdown))

      if (( delta < cooldown )); then
        echo "[MC $uuid] Cooldown ($delta/$cooldown)"
      elif [[ ! -f "$lock" ]]; then
        touch "$lock"
        start_server "$sid"
        echo "[MC $uuid] Start triggered"
        sleep 10
        rm -f "$lock"
      else
        echo "[MC $uuid] Waiting"
      fi

      start_gate "$uuid" "$port"
      sleep 5
    fi
  done
}

main() {
  get_all_servers | while read -r line; do
    uuid=$(echo "$line" | jq -r '.uuid')
    sid=$(echo "$line" | jq -r '.id')
    port=$(get_port "$sid")

    if [[ -z "$port" ]]; then
      echo "[WARN] Skipping $uuid — no port"
      continue
    fi

    watchdog "$uuid" "$sid" "$port" &
  done
  wait
}

main
