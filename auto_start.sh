#!/bin/bash

# Load environment
ENV_FILE=".env"
if [[ -f "$ENV_FILE" ]]; then
  export $(grep -v '^#' "$ENV_FILE" | xargs)
else
  echo ".env file not found!"
  exit 1
fi

UUIDS=($SERVER_UUIDS)  # Space-separated UUIDs
LOCK_DIR="/tmp/ptero-autostart"
mkdir -p "$LOCK_DIR"

get_status() {
  local uuid="$1"
  curl -s -H "Authorization: Bearer $API_KEY" \
       "$PANEL_URL/api/application/servers/$uuid/utilization" |
       jq -r '.attributes.state'
}

get_port() {
  local uuid="$1"
  curl -s -H "Authorization: Bearer $API_KEY" \
       "$PANEL_URL/api/application/servers/$uuid" |
       jq -r '.attributes.allocation | .port'
}

start_server() {
  local uuid="$1"
  curl -s -X POST -H "Authorization: Bearer $API_KEY" \
       -H "Content-Type: application/json" \
       -d '{"signal": "start"}' \
       "$PANEL_URL/api/application/servers/$uuid/power"
  echo "[MC $uuid] Start triggered"
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
  local port
  port=$(get_port "$uuid")
  local last_shutdown=$(date +%s)
  local cooldown=${MIN_OFFLINE:-600}
  local lock="$LOCK_DIR/$uuid.lock"

  while true; do
    local state
    state=$(get_status "$uuid")

    if [[ "$state" == "running" ]]; then
      stop_gate "$uuid"
      while [[ "$(get_status "$uuid")" == "running" ]]; do
        sleep 5
      done
      echo "[MC $uuid] Server stopped"
      last_shutdown=$(date +%s)
    elif [[ "$state" == "starting" ]]; then
      stop_gate "$uuid"
      echo "[MC $uuid] Server is starting..."
      sleep 5
    else
      local now=$(date +%s)
      local delta=$((now - last_shutdown))

      if (( delta < cooldown )); then
        echo "[MC $uuid] Cooldown: $delta/$cooldown"
      elif [[ ! -f "$lock" ]]; then
        touch "$lock"
        start_server "$uuid"
        sleep 10
        rm -f "$lock"
      else
        echo "[MC $uuid] Waiting — already starting"
      fi

      start_gate "$uuid" "$port"
      sleep 5
    fi
  done
}

for uuid in "${UUIDS[@]}"; do
  watchdog "$uuid" &
done

wait
