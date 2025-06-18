#!/bin/bash
set -e

# Install python dependencies
if ! command -v python3 &> /dev/null; then
  echo "Python3 not found, please install it."
  exit 1
fi

if ! python3 -m pip &> /dev/null; then
  echo "pip not found, installing pip..."
  curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py
  python3 get-pip.py
  rm get-pip.py
fi

python3 -m pip install --upgrade requests python-dotenv

# Copy example env if no .env
if [ ! -f .env ]; then
  cp .env.example .env
  echo "Created .env file, please update with your PANEL_URL and API_KEY."
fi

chmod +x autostart_manager.py

echo "Setup done! Run with:"
echo "  python3 autostart_manager.py"
echo "Or set up systemd to run as a service."
