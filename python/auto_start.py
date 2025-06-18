# This is the complete fixed Python autostart manager using Pterodactyl API
# Assumes use of the client API to properly fetch server state: running, starting, offline

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
    "Accept": "Application/vnd.pterodactyl.v1+json",
    "Content-Type": "application/json",
}

GATE_DIR = Path(__file__).parent / "gate"
LOCK_DIR = Path("/tmp")


def is_mc_online(port):
    try:
        with socket.create_connection(("127.0.0.1", port), timeout=1):
            return True
    except Exception:
        return False


def get_server_status(uuid):
    url = f"{PANEL_URL}/api/client/servers/{uuid}/resources"
    try:
        resp = requests.get(url, headers=HEADERS, timeout=5)
        if resp.status_code == 200:
            return resp.json().get("attributes", {}).get("current_state", "offline")
    except Exception as e:
        print(f"[API {uuid}] Error fetching status: {e}")
    return "offline"


def start_gate(uuid, port):
    pid_file = LOCK_DIR / f"gate-{uuid}.pid"
    config_template = GATE_DIR / "gate-config-template.yml"
    config_file = LOCK_DIR / f"gate-{uuid}.yml"

    if pid_file.exists():
        return  # Already running

    with open(config_template) as f:
        config = f.read().replace("{{PORT}}", str(port))
    with open(config_file, "w") as f:
        f.write(config)

    proc = subprocess.Popen(
        [str(GATE_DIR / "gate"), "--config", str(config_file)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL
    )
    pid_file.write_text(str(proc.pid))
    print(f"[GATE {uuid}] Started on port {port}")


def stop_gate(uuid):
    pid_file = LOCK_DIR / f"gate-{uuid}.pid"
    if pid_file.exists():
        try:
            pid = int(pid_file.read_text())
            os.kill(pid, 15)
        except ProcessLookupError:
            pass
        pid_file.unlink()
        print(f"[GATE {uuid}] Stopped")


def start_server(uuid):
    url = f"{PANEL_URL}/api/client/servers/{uuid}/power"
    try:
        requests.post(url, headers=HEADERS, json={"signal": "start"}, timeout=5)
        print(f"[API {uuid}] Server start triggered.")
    except Exception as e:
        print(f"[API {uuid}] Start failed: {e}")


def get_servers():
    url = f"{PANEL_URL}/api/client"
    resp = requests.get(url + "/servers", headers=HEADERS, timeout=5)
    if resp.status_code != 200:
        raise RuntimeError("Unable to fetch server list")
    data = resp.json()
    return [s['attributes']['identifier'] for s in data['data']]


def get_port(uuid):
    url = f"{PANEL_URL}/api/client/servers/{uuid}"
    resp = requests.get(url, headers=HEADERS, timeout=5)
    if resp.status_code != 200:
        return None
    data = resp.json()
    allocations = data['attributes']['relationships']['allocations']['data']
    if allocations:
        return allocations[0]['attributes']['port']
    return None


def watchdog(uuid, port):
    lock_file = LOCK_DIR / f"ptero-autostart-{uuid}.lock"
    last_shutdown = 0

    while True:
        status = get_server_status(uuid)

        if status == "running":
            stop_gate(uuid)
            while get_server_status(uuid) == "running":
                time.sleep(5)
            last_shutdown = time.time()

        elif status == "starting":
            stop_gate(uuid)
            print(f"[MC {uuid}] Server is starting...")
            time.sleep(5)
            continue

        elif status == "offline":
            offline_time = time.time() - last_shutdown
            if offline_time < MIN_OFFLINE:
                print(f"[COOLDOWN {uuid}] {int(offline_time)}/{MIN_OFFLINE}s cooldown.")
            elif not lock_file.exists():
                print(f"[MC {uuid}] Triggering start from ping.")
                lock_file.touch()
                stop_gate(uuid)
                start_server(uuid)
                time.sleep(5)
                lock_file.unlink()
            else:
                print(f"[WAIT {uuid}] Already starting...")

            start_gate(uuid, port)

        time.sleep(5)


def main():
    try:
        servers = get_servers()
    except Exception as e:
        print(f"[ERROR] Could not fetch servers: {e}")
        return

    threads = []
    for uuid in servers:
        try:
            port = get_port(uuid)
            if not port:
                print(f"[WARN] Skipping {uuid} — no port found.")
                continue
            t = threading.Thread(target=watchdog, args=(uuid, port), daemon=True)
            t.start()
            threads.append(t)
        except Exception as e:
            print(f"[ERROR] Could not start watchdog for {uuid}: {e}")

    while True:
        time.sleep(60)


if __name__ == "__main__":
    main()

