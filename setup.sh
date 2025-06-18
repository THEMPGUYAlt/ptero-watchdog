#!/bin/bash
set -euo pipefail

# Check for dependencies
for cmd in jq nc curl; do
  if ! command -v $cmd &>/dev/null; then
    echo "Installing missing dependency: $cmd"
    if [[ -f /etc/debian_version ]]; then
      sudo apt-get update && sudo apt-get install -y $cmd
    elif [[ -f /etc/redhat-release ]]; then
      sudo yum install -y $cmd
    else
      echo "Please install $cmd manually"
      exit 1
    fi
  fi
done

echo "Copy your gate binary to ./gate/gate before running the scripts."

if [[ ! -f .env ]]; then
  echo "Creating .env from .env.example"
  cp .env.example .env
  echo "Please edit .env with your PANEL_URL and API_KEY."
fi

chmod +x server-watchdog.sh autostart-manager.sh gate/gate setup.sh

echo "Setup complete. Run ./autostart-manager.sh to start watchers."

# Optional: Setup systemd service
read -rp "Install systemd service to auto-start manager? (y/n) " ans
if [[ "$ans" == "y" ]]; then
  SERVICE_FILE="/etc/systemd/system/ptero-autostart.service"
  sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=Pterodactyl AutoStart Manager
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$(pwd)
ExecStart=$(pwd)/autostart-manager.sh
Restart=always

[Install]
WantedBy=multi-user.target
EOF

  sudo systemctl daemon-reload
  sudo systemctl enable ptero-autostart
  sudo systemctl start ptero-autostart
  echo "Systemd service installed and started."
fi
