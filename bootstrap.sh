#!/bin/bash
set -e

# Ensure git is available (fresh WSL may not have it)
if ! command -v git &>/dev/null; then
  sudo apt-get update && sudo apt-get install -y git
fi

# Always start fresh — avoids line-ending and merge conflicts
rm -rf ~/fnwsl
git clone -c core.autocrlf=input https://github.com/fnrhombus/fnwsl ~/fnwsl

cd ~/fnwsl
chmod +x install.sh
bash -c './install.sh "$@" < /dev/tty' -- "$@"
