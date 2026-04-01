#!/bin/bash
set -e

# Ensure git is available (fresh WSL may not have it)
if ! command -v git &>/dev/null; then
  sudo apt-get update && sudo apt-get install -y git
fi

# Clone and run
git clone https://github.com/fnrhombus/fnwsl ~/fnwsl
cd ~/fnwsl
chmod +x install.sh
./install.sh
