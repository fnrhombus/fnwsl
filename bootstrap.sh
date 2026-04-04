#!/bin/bash
set -e

# Fix WSL2 MTU immediately (prevents TLS/SSL failures on large downloads)
iface=$(ip route show default 2>/dev/null | awk '{print $5; exit}')
[ -n "$iface" ] && sudo ip link set dev "$iface" mtu 1350

# Ensure git is available (fresh WSL may not have it)
if ! command -v git &>/dev/null; then
  sudo apt-get update && sudo apt-get install -y git
fi

# Always start fresh — avoids line-ending and merge conflicts
rm -rf ~/fnwsl
GIT_TEMPLATE_DIR="" git clone -c core.autocrlf=input https://github.com/fnrhombus/fnwsl ~/fnwsl

cd ~/fnwsl
chmod +x install.sh
bash -c './install.sh "$@" < /dev/tty' -- "$@"
