#!/bin/bash
set -e

SSH_PASSPHRASE="${1:-}"
WSL_NAME="${2:-}"
P10K_WIZARD="${3:-}"

echo "=== fnwsl setup ==="

# --- Fix WSL2 stack limit (prevents native binary crashes under WSL) ---
ulimit -s unlimited

# --- Fix WSL2 MTU (prevents TLS/SSL failures on large downloads) ---
if ip link show eth0 &>/dev/null; then
  sudo ip link set dev eth0 mtu 1350
fi

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

# --- Install tools via mise ---
echo ""
echo "Installing tools via mise..."
~/.local/bin/mise use -g sd
~/.local/bin/mise use -g yq
~/.local/bin/mise use -g xh
~/.local/bin/mise use -g gh
~/.local/bin/mise use -g zoxide
~/.local/bin/mise use -g claude-code
~/.local/bin/mise trust ~/.config/mise/config.toml 2>/dev/null || true

# --- WSL hostname and boot config ---
if [[ -n "$WSL_NAME" ]]; then
  WSL_HOSTNAME="$WSL_NAME"
else
  WIN_HOSTNAME=$(hostname.exe 2>/dev/null | tr -d '\r' | tr '[:upper:]' '[:lower:]')
  WSL_HOSTNAME="${WIN_HOSTNAME}-wsl"
fi
if ! grep -q "hostname=" /etc/wsl.conf 2>/dev/null; then
  echo ""
  echo "Setting WSL hostname to ${WSL_HOSTNAME}..."
  sudo tee -a /etc/wsl.conf > /dev/null <<EOF

[network]
hostname=${WSL_HOSTNAME}
EOF
fi
if ! grep -q "systemd=" /etc/wsl.conf 2>/dev/null; then
  sudo tee -a /etc/wsl.conf > /dev/null <<EOF

[boot]
systemd=true
command=/sbin/ip link set dev eth0 mtu 1350
EOF
elif ! grep -q "command=" /etc/wsl.conf 2>/dev/null; then
  sudo sed -i '/\[boot\]/a command=/sbin/ip link set dev eth0 mtu 1350' /etc/wsl.conf
fi
if ! grep -q "appendWindowsPath" /etc/wsl.conf 2>/dev/null; then
  echo ""
  echo "Disabling Windows PATH inheritance (prevents tool conflicts)..."
  sudo tee -a /etc/wsl.conf > /dev/null <<EOF

[interop]
appendWindowsPath=false
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

# --- Pre-clone zgenom (avoids git template race on first zsh login) ---
if [[ ! -d ~/.zgenom ]]; then
  echo "Pre-cloning zgenom..."
  git clone https://github.com/jandamm/zgenom.git ~/.zgenom
fi

# --- Symlink Windows Claude settings (after stow to avoid path confusion) ---
if [[ -d /mnt/d/Users/Tom/.claude ]] && [[ ! -L ~/.claude ]]; then
  echo ""
  echo "Symlinking Windows Claude settings..."
  [[ -d ~/.claude ]] && mv ~/.claude ~/.claude.bak
  ln -s /mnt/d/Users/Tom/.claude ~/.claude
fi

# --- Powerlevel10k config (suppress wizard by default) ---
if [[ -z "$P10K_WIZARD" ]]; then
  ln -sf "$SCRIPT_DIR/config/p10k.zsh" ~/.p10k.zsh
  echo "  Installed p10k config (use -P10kWizard to run the wizard instead)"
fi

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
if ~/.local/bin/mise exec -- gh auth status &>/dev/null; then
  echo ""
  echo "Registering SSH key with GitHub..."
  ~/.local/bin/mise exec -- gh ssh-key add ~/.ssh/id_ed25519.pub --title "$(hostname) - WSL" --type authentication 2>/dev/null || true
  ~/.local/bin/mise exec -- gh ssh-key add ~/.ssh/id_ed25519.pub --type signing 2>/dev/null || true
else
  # Plant a self-deleting login script for first interactive session
  echo ""
  echo "No GitHub token found — deferring gh auth to first login."
  sudo tee /etc/profile.d/fnwsl-gh-setup.sh > /dev/null <<'GHEOF'
#!/bin/bash
# fnwsl: one-time GitHub auth + SSH key registration (self-deleting)
if [ -t 0 ] && command -v gh &>/dev/null; then
  echo ""
  echo "=== fnwsl: GitHub authentication ==="
  echo "Authenticate with GitHub to register your SSH key for git signing."
  echo ""
  if gh auth login; then
    gh ssh-key add ~/.ssh/id_ed25519.pub --title "$(hostname) - WSL" --type authentication 2>/dev/null || true
    gh ssh-key add ~/.ssh/id_ed25519.pub --type signing 2>/dev/null || true
    echo ""
    echo "SSH key registered with GitHub."
  fi
  sudo rm -f /etc/profile.d/fnwsl-gh-setup.sh
fi
GHEOF
fi

# --- SSH server (port 2222, avoids conflict with Windows sshd on 22) ---
if ! dpkg -s openssh-server &>/dev/null; then
  echo ""
  echo "Installing SSH server..."
  sudo apt-get install -y openssh-server || true
  # Ubuntu 24.04 uses socket activation - override the port in the systemd unit
  sudo mkdir -p /etc/systemd/system/ssh.socket.d
  sudo tee /etc/systemd/system/ssh.socket.d/override.conf > /dev/null <<'EOF'
[Socket]
ListenStream=
ListenStream=2222
EOF
  # Also set in sshd_config for direct-start compatibility
  sudo sed -i 's/^#Port 22$/Port 2222/' /etc/ssh/sshd_config
  sudo sed -i 's/^Port 22$/Port 2222/' /etc/ssh/sshd_config
  if pidof systemd &>/dev/null; then
    sudo systemctl daemon-reload
    sudo systemctl enable ssh.socket
    sudo systemctl restart ssh.socket
  fi
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

# --- Verify installation ---
echo ""
echo "Verifying installation..."
VERIFY_FAILURES=()

# Activate mise so its tools are on PATH (mirrors what .zshrc does)
eval "$(~/.local/bin/mise activate bash)" 2>/dev/null
export PATH="$HOME/.local/bin:$PATH"

verify() {
  local label="$1"
  local check="$2"
  if eval "$check" &>/dev/null; then
    echo "  OK  $label"
  else
    echo "  FAIL  $label"
    VERIFY_FAILURES+=("$label")
  fi
}

# Shell
verify "zsh is default shell" "[[ \$(getent passwd \$USER | cut -d: -f7) == */zsh ]]"

# All tools on PATH (apt and mise alike)
for cmd in zsh fzf bat fd rg eza lsd tmux stow jq btop keychain direnv tldr sd yq xh gh zoxide claude mise; do
  case "$cmd" in
    bat) verify "$cmd on PATH" "command -v bat || command -v batcat" ;;
    fd)  verify "$cmd on PATH" "command -v fd || command -v fdfind" ;;
    *)   verify "$cmd on PATH" "command -v $cmd" ;;
  esac
done

# SSH
verify "SSH key" "[[ -f ~/.ssh/id_ed25519 ]]"
verify "SSH allowed_signers" "[[ -f ~/.ssh/allowed_signers ]]"
verify "SSH config symlink" "[[ -L ~/.ssh/config ]]"

# Dotfiles
verify ".zshrc symlink" "[[ -L ~/.zshrc ]]"
verify ".gitconfig symlink" "[[ -L ~/.gitconfig ]]"
verify ".tmux.conf symlink" "[[ -L ~/.tmux.conf ]]"
verify ".p10k.zsh" "[[ -f ~/.p10k.zsh ]]"

# wsl.conf
verify "wsl.conf hostname" "grep -q 'hostname=' /etc/wsl.conf"
verify "wsl.conf systemd" "grep -q 'systemd=true' /etc/wsl.conf"
verify "wsl.conf MTU boot cmd" "grep -q 'mtu 1350' /etc/wsl.conf"
verify "wsl.conf appendWindowsPath=false" "grep -q 'appendWindowsPath=false' /etc/wsl.conf"

# udev rules
verify "udev USB serial rules" "[[ -f /etc/udev/rules.d/99-usb-serial.rules ]]"

if [[ ${#VERIFY_FAILURES[@]} -gt 0 ]]; then
  echo ""
  echo "WARNING: ${#VERIFY_FAILURES[@]} check(s) failed:" >&2
  for f in "${VERIFY_FAILURES[@]}"; do
    echo "  - $f" >&2
  done
fi

echo ""
echo "=== Setup complete ==="
echo ""
echo "Next steps:"
echo "  1. Run 'wsl --shutdown' from Windows, then relaunch WSL"
echo "  2. If not logged into gh: run 'gh auth login'"
echo "  3. Verify git signing: git log --show-signature"
echo "  4. To reconfigure p10k prompt: p10k configure"
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
