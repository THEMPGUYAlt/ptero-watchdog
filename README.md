# 🟢 Pterodactyl Minecraft Auto-Starter

Automatically starts any Minecraft server on your Pterodactyl panel when a player attempts to connect — saving resources while offering seamless auto-start behavior.

## ✅ Features

- 🧠 Detects when players ping/join an offline server
- 🚀 Starts the correct server using the Pterodactyl API
- 🔁 Resumes listening when the server shuts down
- 🧩 Works with any number of servers

---

## 🛠️ Requirements

- Linux server (with public access to MC ports)
- Bash, `curl`, `jq`, `nc` (see `requirements.txt`)
- A **Pterodactyl Application API key**

---

## ⚙️ Setup

**Important! Make sure it is on the wings backend**

1. Clone the repo:

```bash
git clone git@github.com:Ifixthingz383/ptero-watchdog.git
cd ptero-watchdog
```
2. Edit the env:

```bash
nano .env
```

3. Run the script (I recommend on screen)
```bash
chmod +x auto_start.sh
(Optional) screen -S PanelAutoStart
./auto_start.sh
```
