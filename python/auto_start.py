#!/usr/bin/env python3
import os
import time
import socket
import subprocess
import threading
from pathlib import Path

import requests
from dotenv import load_dotenv

load_dotenv()

PANEL_URL = os.getenv("PANEL_URL")
API_KEY = os.getenv("API_KEY")
MIN_OFFLINE = int(os.getenv("MIN_OFFLINE", 600))

HEADERS = {
    "Authorization": f"Bearer {API_KEY}",
    "Content-Type": "application/json",
}

GATE_DIR = Path(__file__).parent / "gate"
LOCK_DIR = Path("/tmp")

def is_mc_online(port):
    try:
        with socket.create_connection(("127.0.0.1", port), timeout=1):
            return True
    except (OSError, ConnectionRefusedError):
        return False

def start_gate(uuid, port):
    pid_file = LOCK_DIR / f"gate-{uuid}.pid"
    config_template = GATE_DIR / "gate-config-template.yml"
    config_file = LOCK_DIR / f"gate-{uuid}.yml"

    if pid_file.exists():
        print(f"[GATE {uuid}] Gate already running")
        return

    with open(config_template, "r") as f:
        config_data = f.read()
    config_data = config_data.replace("{{PORT}}", str(port))

    with open(config_file, "w") as f:
        f.write(config_data)

    print(f"[GATE {uuid}] Starting Gate proxy on port {port}")
    proc = subprocess.Popen(
        [str(GATE_DIR / "gate"), "--config", str(config_file)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    pid_file.write_text(str(proc.pid))

def stop_gate(uuid):
    pid_file = LOCK_DIR / f"gate-{uuid}.pid"
    if pid_file.exists():
        pid = int(pid_file.read_text())
        try:
            os.kill(pid, 15)  # SIGTERM
            print(f"[GATE {uuid}] Stopped")
        except ProcessLookupError:
            pass
        pid_file.unlink()

def start_server(uuid):
    print(f"[API {uuid}] Sending start signal to Pterodactyl API")
    url = f"{PANEL_URL}/api/application/servers/{uuid}/power"
    resp = requests.post(
        url,
        headers=HEADERS,
        json={"signal": "start"},
        timeout=10,
    )
    if resp.status_code == 204:
        print(f"[API {uuid}] Server start request sent successfully")
    else:
        print(f"[API {uuid}] Failed to start server: {resp.status_code} - {resp.text}")

def get_servers():
    url = f"{PANEL_URL}/api/application/servers"
    resp = requests.get(url, headers=HEADERS, timeout=10)
    resp.raise_for_status()
    data = resp.json()
    return [srv["attributes"]["uuid"] for srv in data.get("data", [])]

def get_port(uuid):
    url = f"{PANEL_URL}/api/application/servers/{uuid}/allocations"
    resp = requests.get(url, headers=HEADERS, timeout=10)
    resp.raise_for_status()
    data = resp.json()
    allocs = data.get("data", [])
    if allocs:
        return allocs[0]["attributes"]["port"]
    return None

def watchdog(uuid, port):
    lock_file = LOCK_DIR / f"ptero-autostart-{uuid}.lock"
    last_shutdown = 0

    while True:
        if is_mc_online(port):
            stop_gate(uuid)
            print(f"[MC {uuid}] Server online")
            while is_mc_online(port):
                time.sleep(5)
            print(f"[MC {uuid}] Server stopped")
            last_shutdown = time.time()
        else:
            offline_time = time.time() - last_shutdown
            if offline_time < MIN_OFFLINE:
                print(f"[COOLDOWN {uuid}] Waiting cooldown {int(offline_time)}/{MIN_OFFLINE}s")
            else:
                if not lock_file.exists():
                    print(f"[PING {uuid}] Offline ping detected, starting server")
                    lock_file.touch()
                    stop_gate(uuid)
                    start_server(uuid)
                    while not is_mc_online(port):
                        time.sleep(2)
                    lock_file.unlink()
                else:
                    print(f"[WAIT {uuid}] Server is starting...")
            start_gate(uuid, port)
            time.sleep(5)

def main():
    try:
        servers = get_servers()
    except Exception as e:
        print(f"[ERROR] Failed to fetch servers from panel: {e}")
        return

    threads = []
    for uuid in servers:
        try:
            port = get_port(uuid)
            if port is None:
                print(f"[MANAGER] No port for {uuid}, skipping")
                continue
            print(f"[MANAGER] Launching watchdog for {uuid} on port {port}")
            t = threading.Thread(target=watchdog, args=(uuid, port), daemon=True)
            t.start()
            threads.append(t)
        except Exception as e:
            print(f"[ERROR] Failed to init watchdog for {uuid}: {e}")

    while True:
        time.sleep(60)

if __name__ == "__main__":
    main()
