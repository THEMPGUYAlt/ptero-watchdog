import os
import time
import subprocess
import requests
import threading
from pathlib import Path

# Load environment
from dotenv import load_dotenv
load_dotenv()

PANEL_URL = os.getenv("PANEL_URL")
API_KEY = os.getenv("API_KEY")
MIN_OFFLINE = int(os.getenv("MIN_OFFLINE", "600"))
LOCK_DIR = Path("/tmp/ptero-autostart")
LOCK_DIR.mkdir(parents=True, exist_ok=True)

HEADERS = {
    "Authorization": f"Bearer {API_KEY}",
    "Accept": "application/json",
    "Content-Type": "application/json"
}

def get_all_servers():
    url = f"{PANEL_URL}/api/application/servers"
    try:
        r = requests.get(url, headers=HEADERS, timeout=10)
        return [
            {
                "uuid": s["attributes"]["uuid"],
                "id": s["attributes"]["id"],
                "port": s["attributes"]["allocation"]["port"]
            }
            for s in r.json()["data"]
        ]
    except Exception as e:
        print(f"[ERROR] Fetching server list failed: {e}")
        return []

def get_status(sid):
    url = f"{PANEL_URL}/api/application/servers/{sid}/utilization"
    try:
        r = requests.get(url, headers=HEADERS, timeout=5)
        return r.json()["attributes"]["state"]
    except:
        return "offline"

def start_server(sid):
    url = f"{PANEL_URL}/api/application/servers/{sid}/power"
    try:
        requests.post(url, headers=HEADERS, json={"signal": "start"}, timeout=5)
        print(f"[MC {sid}] Server start triggered")
    except Exception as e:
        print(f"[MC {sid}] Failed to start: {e}")

def start_gate(uuid, port):
    pid_file = LOCK_DIR / f"{uuid}.gate.pid"
    if pid_file.exists():
        return  # Already running

    proc = subprocess.Popen(
        ["gate", "--port", str(port), "--message", "§aThis server is offline, please wait."],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL
    )
    pid_file.write_text(str(proc.pid))
    print(f"[GATE {uuid}] Listening on port {port}")

def stop_gate(uuid):
    pid_file = LOCK_DIR / f"{uuid}.gate.pid"
    if pid_file.exists():
        try:
            os.kill(int(pid_file.read_text()), 15)
        except:
            pass
        pid_file.unlink()
        print(f"[GATE {uuid}] Stopped")

def watchdog(uuid, sid, port):
    lock = LOCK_DIR / f"{uuid}.lock"
    last_shutdown = time.time() - MIN_OFFLINE

    while True:
        state = get_status(sid)

        if state == "running":
            stop_gate(uuid)
            while get_status(sid) == "running":
                time.sleep(5)
            last_shutdown = time.time()
            print(f"[MC {uuid}] Server stopped")

        elif state == "starting":
            stop_gate(uuid)
            print(f"[MC {uuid}] Starting...")
            time.sleep(5)

        else:
            cooldown_left = time.time() - last_shutdown
            if cooldown_left < MIN_OFFLINE:
                print(f"[MC {uuid}] Cooldown: {int(cooldown_left)}s")
            elif not lock.exists():
                lock.touch()
                print(f"[MC {uuid}] Triggering start")
                stop_gate(uuid)
                start_server(sid)
                time.sleep(10)
                lock.unlink()
            else:
                print(f"[MC {uuid}] Already starting...")

            start_gate(uuid, port)

        time.sleep(5)

def main():
    servers = get_all_servers()
    if not servers:
        print("[ERROR] No servers found.")
        return

    for server in servers:
        if not server["port"]:
            continue
        threading.Thread(
            target=watchdog,
            args=(server["uuid"], server["id"], server["port"]),
            daemon=True
        ).start()

    while True:
        time.sleep(60)

if __name__ == "__main__":
    main()
