#!/bin/bash
set -e

# Ensure git is available (fresh WSL may not have it)
if ! command -v git &>/dev/null; then
  sudo apt-get update && sudo apt-get install -y git
fi

# Clone or pull latest
if [[ -d ~/fnwsl ]]; then
  echo "~/fnwsl already exists, pulling latest..."
  git -C ~/fnwsl pull
else
  git clone https://github.com/fnrhombus/fnwsl ~/fnwsl
fi

# Run install.sh with a proper tty (curl pipes break interactive prompts)
cd ~/fnwsl
chmod +x install.sh
bash -c "./install.sh $* < /dev/tty"
