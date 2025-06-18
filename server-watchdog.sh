#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/.env"

UUID="$1"
PORT="$2"
LOCK="/tmp/ptero-autostart-${UUID}.lock"
GATE_DIR="$(dirname "$0")/gate"
GATE_PID_FILE="/tmp/gate-${UUID}.pid"
GATE_CONFIG="/tmp/gate-${UUID}.yml"

MIN_OFFLINE=600  # 10 min cooldown between restarts
last_shutdown=0

start_gate() {
  if [[ ! -f "$GATE_PID_FILE" ]]; then
    sed "s/{{PORT}}/$PORT/g" "$GATE_DIR/gate-config-template.yml" > "$GATE_CONFIG"
    echo "[GATE $UUID] Starting Gate on port $PORT"
    nohup "$GATE_DIR/gate" --config "$GATE_CONFIG" > /dev/null 2>&1 &
    echo $! > "$GATE_PID_FILE"
  fi
}

stop_gate() {
  if [[ -f "$GATE_PID_FILE" ]]; then
    kill "$(cat "$GATE_PID_FILE")" 2>/dev/null || true
    rm -f "$GATE_PID_FILE"
    echo "[GATE $UUID] Stopped"
  fi
}

is_mc_online() {
  nc -z -w1 127.0.0.1 "$PORT"
}

start_server() {
  echo "[API $UUID] Auto-start triggered"
  curl -s -X POST "$PANEL_URL/api/application/servers/$UUID/power" \
    -H "Authorization: Bearer $API_KEY" \
    -H "Content-Type: application/json" \
    -d '{"signal":"start"}' > /dev/null
}

while true; do
  if is_mc_online; then
    stop_gate
    echo "[MC $UUID] Server online"
    while is_mc_online; do sleep 5; done
    echo "[MC $UUID] Server stopped"
    last_shutdown=$(date +%s)
  else
    now=$(date +%s)
    offline_time=$((now - last_shutdown))
    if (( offline_time < MIN_OFFLINE )); then
      echo "[COOLDOWN $UUID] Server offline but cooldown active ($offline_time/$MIN_OFFLINE sec), skipping auto-start"
    else
      if [[ ! -f "$LOCK" ]]; then
        echo "[PING $UUID] Offline ping detected — triggering start"
        touch "$LOCK"
        stop_gate
        start_server
        until is_mc_online; do sleep 2; done
        rm -f "$LOCK"
      else
        echo "[WAIT $UUID] Server is starting..."
      fi
    fi

    start_gate
    sleep 5
  fi
done
