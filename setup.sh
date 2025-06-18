#!/bin/bash

set -e

REPO_URL="https://github.com/YOUR_USERNAME/ptero-autostart.git"
INSTALL_DIR="$HOME/ptero-autostart"
SERVICE_NAME="ptero-autostart"

echo "== Pterodactyl Minecraft Auto-Start Setup =="

# Check and install dependencies
for pkg in curl jq netcat; do
  if ! command -v $pkg &>/dev/null; then
    echo "Installing $pkg..."
    if command -v apt-get &>/dev/null; then
      sudo apt-get update
      sudo apt-get install -y $pkg
    else
      echo "Please install $pkg manually and rerun the script."
      exit 1
    fi
  fi
done

# Clone or update repo
if [ -d "$INSTALL_DIR" ]; then
  echo "Updating existing installation..."
  git -C "$INSTALL_DIR" pull
else
  echo "Cloning repository..."
  git clone "$REPO_URL" "$INSTALL_DIR"
fi

cd "$INSTALL_DIR"

# Overwrite .env file
echo "Configuring .env file (this will overwrite existing .env)..."
read -rp "Enter your Pterodactyl Panel URL (e.g. https://panel.example.com): " PANEL_URL
read -rp "Enter your Application API Key: " API_KEY
cat > .env <<EOF
PANEL_URL="$PANEL_URL"
API_KEY="$API_KEY"
EOF
echo ".env file created."

# Make script executable
chmod +x auto_start.sh

# Ask to create systemd service (if systemd exists)
if command -v systemctl &>/dev/null && systemctl --version &>/dev/null; then
  read -rp "Do you want to install and start the systemd service? (y/N): " install_svc
  if [[ "$install_svc" =~ ^[Yy]$ ]]; then
    echo "Creating systemd service..."

    SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
    sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=Pterodactyl Minecraft Auto-Start Script
After=network.target

[Service]
Type=simple
User=$(whoami)
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/auto_start.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable "$SERVICE_NAME"
    sudo systemctl start "$SERVICE_NAME"
    echo "Systemd service started and enabled."
  else
    echo "Skipping systemd service setup. Starting script manually in background."
    nohup "$INSTALL_DIR/auto_start.sh" > "$INSTALL_DIR/auto_start.log" 2>&1 &
    echo "Script started in background with nohup."
  fi
else
  echo "Systemd not detected. Starting script with nohup in background."
  nohup "$INSTALL_DIR/auto_start.sh" > "$INSTALL_DIR/auto_start.log" 2>&1 &
  echo "Script started in background with nohup."
fi

echo "Setup complete!"
