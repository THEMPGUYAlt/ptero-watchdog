#!/bin/bash

# Load config from .env
source "$(dirname "$0")/.env"

CHECK_INTERVAL=5
LISTENERS_DIR="/tmp/ptero_listeners"
mkdir -p "$LISTENERS_DIR"

# Get all servers
get_all_servers() {
  curl -s -X GET "$PANEL_URL/api/application/servers" \
    -H "Authorization: Bearer $API_KEY" \
    -H "Content-Type: application/json"
}

# Get allocated IP:PORTs for a server
get_server_ports() {
  local server_id="$1"
  curl -s -X GET "$PANEL_URL/api/application/servers/$server_id/allocations" \
    -H "Authorization: Bearer $API_KEY" \
    -H "Content-Type: application/json" | jq -r '.data[] | "\(.attributes.ip):\(.attributes.port)"'
}

# Start server via API
start_server() {
  local server_id="$1"
  echo "[INFO] Starting server $server_id"
  curl -s -X POST "$PANEL_URL/api/application/servers/$server_id/power" \
    -H "Authorization: Bearer $API_KEY" \
    -H "Content-Type: application/json" \
    -d '{"signal": "start"}' > /dev/null
}

# Check if a port is live
is_port_live() {
  nc -z -w1 "$1" "$2"
  return $?
}

# Launch listener loop for a server
listen_on_port() {
  local server_id="$1"
  local ip="$2"
  local port="$3"
  local listener_pid_file="$LISTENERS_DIR/$server_id-$port.pid"

  echo "[LISTEN] $server_id → $ip:$port"

  while true; do
    nc -lk -s "$ip" -p "$port" -c "echo -e '\x00'; exit" &
    listener_pid=$!
    echo $listener_pid > "$listener_pid_file"
    wait $listener_pid

    echo "[PING] $ip:$port → Starting server $server_id"
    start_server "$server_id"

    until is_port_live "$ip" "$port"; do sleep $CHECK_INTERVAL; done
    echo "[READY] Server $server_id is online on $port"

    while is_port_live "$ip" "$port"; do sleep $CHECK_INTERVAL; done
    echo "[DOWN] Server $server_id has stopped"
  done
}

# Main loop
echo "[INIT] Starting auto-start service..."

servers=$(get_all_servers | jq -r '.data[] | "\(.attributes.id)"')

for server_id in $servers; do
  ports=$(get_server_ports "$server_id")
  for addr in $ports; do
    ip=$(echo $addr | cut -d ':' -f1)
    port=$(echo $addr | cut -d ':' -f2)

    if is_port_live "$ip" "$port"; then
      echo "[SKIP] $ip:$port is already active"
    else
      listen_on_port "$server_id" "$ip" "$port" &
    fi
  done
done
