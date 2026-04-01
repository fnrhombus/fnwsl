#!/bin/bash
set -e

SSH_PASSPHRASE="${1:-}"

echo "=== fnwsl setup ==="

# --- System packages (retry once on hash mismatch) ---
install_packages() {
  sudo apt-get install -y \
    zsh \
    keychain \
    fzf \
    stow \
    bat \
    fd-find \
    lsd \
    ripgrep \
    eza \
    tmux \
    tldr \
    git \
    jq \
    btop \
    curl \
    wget
}
sudo apt-get update
install_packages || {
  echo "Package install failed, retrying after clean update..."
  sudo apt-get clean
  sudo apt-get update
  install_packages
}

# --- Set zsh as default shell ---
if [[ "$SHELL" != */zsh ]]; then
  sudo chsh -s /bin/zsh "$USER"
  echo "Default shell changed to zsh. Will take effect on next login."
fi

# --- SSH key ---
if [[ ! -f ~/.ssh/id_ed25519 ]]; then
  echo ""
  echo "Generating SSH key..."
  if [[ -n "$SSH_PASSPHRASE" ]]; then
    ssh-keygen -t ed25519 -C "2511516+fnrhombus@users.noreply.github.com" -f ~/.ssh/id_ed25519 -N "$SSH_PASSPHRASE"
  else
    ssh-keygen -t ed25519 -C "2511516+fnrhombus@users.noreply.github.com" -f ~/.ssh/id_ed25519
  fi
fi

# --- Install GitHub CLI ---
if ! command -v gh &>/dev/null; then
  echo ""
  echo "Installing GitHub CLI..."
  (type -p wget >/dev/null || (sudo apt update && sudo apt-get install wget -y)) \
    && sudo mkdir -p -m 755 /etc/apt/keyrings \
    && wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
    && sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && sudo apt update \
    && sudo apt install gh -y
fi

# --- Install mise (tool version manager) ---
if ! command -v mise &>/dev/null; then
  echo ""
  echo "Installing mise..."
  curl https://mise.run | sh
fi

# --- Install direnv (per-directory env vars) ---
if ! command -v direnv &>/dev/null; then
  echo ""
  echo "Installing direnv..."
  sudo apt-get install -y direnv
fi

# --- Install zoxide (smart cd) ---
if ! command -v zoxide &>/dev/null; then
  echo ""
  echo "Installing zoxide..."
  curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh
fi

# --- Install tools via mise ---
echo ""
echo "Installing tools via mise..."
~/.local/bin/mise use -g sd
~/.local/bin/mise use -g yq
~/.local/bin/mise use -g xh

# --- Install Claude Code ---
if ! command -v claude &>/dev/null; then
  echo ""
  echo "Installing Claude Code..."
  for i in 1 2 3; do
    curl -fsSL https://claude.ai/install.sh | bash && break
    echo "  Attempt $i failed, retrying..."
    sleep 2
  done
fi

# --- Symlink Windows Claude settings ---
if [[ -d /mnt/d/Users/Tom/.claude ]] && [[ ! -L ~/.claude ]]; then
  echo ""
  echo "Symlinking Windows Claude settings..."
  [[ -d ~/.claude ]] && mv ~/.claude ~/.claude.bak
  ln -s /mnt/d/Users/Tom/.claude ~/.claude
fi

# --- WSL hostname (windows-hostname + "-wsl") ---
WIN_HOSTNAME=$(hostname.exe 2>/dev/null | tr -d '\r' | tr '[:upper:]' '[:lower:]')
WSL_HOSTNAME="${WIN_HOSTNAME}-wsl"
if ! grep -q "hostname=" /etc/wsl.conf 2>/dev/null; then
  echo ""
  echo "Setting WSL hostname to ${WSL_HOSTNAME}..."
  sudo tee -a /etc/wsl.conf > /dev/null <<EOF

[network]
hostname=${WSL_HOSTNAME}

[boot]
systemd=true
EOF
fi

# --- Stow dotfiles ---
echo ""
echo "Stowing dotfiles..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Back up existing files that would conflict
for f in ~/.zshrc ~/.zsh_aliases ~/.gitconfig ~/.tmux.conf; do
  if [[ -f "$f" && ! -L "$f" ]]; then
    mv "$f" "${f}.bak"
    echo "  Backed up $f → ${f}.bak"
  fi
done

stow --restow --target="$HOME" zsh
stow --restow --target="$HOME" git
stow --restow --target="$HOME" tmux

# SSH config needs special handling (into ~/.ssh/)
mkdir -p ~/.ssh
chmod 700 ~/.ssh
if [[ -f ~/.ssh/config && ! -L ~/.ssh/config ]]; then
  mv ~/.ssh/config ~/.ssh/config.bak
  echo "  Backed up ~/.ssh/config → ~/.ssh/config.bak"
fi
ln -sf "$SCRIPT_DIR/ssh/config" ~/.ssh/config
chmod 600 ~/.ssh/config

# --- Allowed signers for SSH commit verification ---
if [[ -f ~/.ssh/id_ed25519.pub ]]; then
  echo "2511516+fnrhombus@users.noreply.github.com $(cat ~/.ssh/id_ed25519.pub)" > ~/.ssh/allowed_signers
fi

# --- Register SSH key with GitHub ---
if command -v gh &>/dev/null && gh auth status &>/dev/null; then
  echo ""
  echo "Registering SSH key with GitHub..."
  gh ssh-key add ~/.ssh/id_ed25519.pub --title "$(hostname) - WSL" --type authentication 2>/dev/null || true
  gh ssh-key add ~/.ssh/id_ed25519.pub --type signing 2>/dev/null || true
fi

# --- SSH server (port 2222, avoids conflict with Windows sshd on 22) ---
if ! dpkg -s openssh-server &>/dev/null; then
  echo ""
  echo "Installing SSH server..."
  sudo apt-get install -y openssh-server
  sudo sed -i 's/^#Port 22$/Port 2222/' /etc/ssh/sshd_config
  sudo sed -i 's/^Port 22$/Port 2222/' /etc/ssh/sshd_config
  sudo systemctl enable ssh
  sudo systemctl start ssh
fi

# --- USB serial udev rules (ESP32 / Pi Pico) ---
if [[ ! -f /etc/udev/rules.d/99-usb-serial.rules ]]; then
  echo ""
  echo "Adding udev rules for ESP32 and Pi Pico..."
  sudo tee /etc/udev/rules.d/99-usb-serial.rules > /dev/null <<'EOF'
# CP2102/CP2104 (ESP32 dev boards)
SUBSYSTEM=="tty", ATTRS{idVendor}=="10c4", ATTRS{idProduct}=="ea60", MODE="0666", GROUP="dialout"
# CH340 (cheap ESP32 clones)
SUBSYSTEM=="tty", ATTRS{idVendor}=="1a86", ATTRS{idProduct}=="7523", MODE="0666", GROUP="dialout"
# RP2040 (Pi Pico) — REPL
SUBSYSTEM=="tty", ATTRS{idVendor}=="2e8a", ATTRS{idProduct}=="0003", MODE="0666", GROUP="dialout"
# RP2040 (Pi Pico) — MicroPython
SUBSYSTEM=="tty", ATTRS{idVendor}=="2e8a", ATTRS{idProduct}=="0005", MODE="0666", GROUP="dialout"
# FTDI (various dev boards)
SUBSYSTEM=="tty", ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6001", MODE="0666", GROUP="dialout"
EOF
  sudo udevadm control --reload
  sudo usermod -aG dialout "$USER"
fi

echo ""
echo "=== Setup complete ==="
echo ""
echo "Next steps:"
echo "  1. Run 'wsl --shutdown' from Windows, then relaunch WSL"
echo "  2. Powerlevel10k will prompt you to configure your prompt"
echo "  3. If not logged into gh: run 'gh auth login'"
echo "  4. Verify git signing: git log --show-signature"
echo ""
echo "Windows-side setup (run in elevated PowerShell):"
echo "  5. Enable mirrored networking: create %UserProfile%\\.wslconfig with:"
echo "       [wsl2]"
echo "       networkingMode=mirrored"
echo "       dnsTunneling=true"
echo "       firewall=true"
echo "  6. Allow inbound to WSL (for SSH, HTTP servers):"
echo "       Set-NetFirewallHyperVVMSetting -Name '{40E0AC32-46A5-438A-A0B2-2B479E8F2E90}' -DefaultInboundAction Allow"
echo "  7. Install usbipd for ESP32/Pico USB passthrough:"
echo "       winget install dorssel.usbipd-win"
echo "  8. Attach USB device: usbipd bind --busid X-X && usbipd attach --wsl --busid X-X --auto-attach"
