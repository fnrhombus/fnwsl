#!/bin/bash
set -e

SSH_PASSPHRASE="${1:-}"
WSL_NAME="${2:-}"
P10K_WIZARD="${3:-}"

echo "=== fnwsl setup ==="

# --- Fix WSL2 stack limit (prevents native binary crashes under WSL) ---
ulimit -s unlimited

# --- Fix WSL2 MTU (prevents TLS/SSL failures on large downloads) ---
WSL_IFACE=$(ip route show default 2>/dev/null | awk '{print $5; exit}')
if [[ -n "$WSL_IFACE" ]]; then
  sudo ip link set dev "$WSL_IFACE" mtu 1350
fi
# Persist as boot script (interface name may vary across reboots)
sudo tee /usr/local/bin/fix-mtu.sh > /dev/null <<'MTUSCRIPT'
#!/bin/sh
iface=$(ip route show default | head -1 | awk '{print $5}')
[ -n "$iface" ] && ip link set dev "$iface" mtu 1350
MTUSCRIPT
sudo chmod +x /usr/local/bin/fix-mtu.sh

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
  ssh-keygen -t ed25519 -C "$(hostname)" -f ~/.ssh/id_ed25519 -N "$SSH_PASSPHRASE"
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
mise_install() {
  local tool="$1" attempt
  for attempt in 1 2 3; do
    if ~/.local/bin/mise use -g "$tool"; then return 0; fi
    echo "  Retrying $tool (attempt $((attempt+1))/3)..."
    sleep 2
  done
  echo "ERROR: Failed to install $tool after 3 attempts" >&2
  return 1
}
mise_install sd
mise_install yq
mise_install xh
mise_install gh
mise_install zoxide
mise_install claude-code
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
command=/usr/local/bin/fix-mtu.sh
EOF
elif ! grep -q "command=" /etc/wsl.conf 2>/dev/null; then
  sudo sed -i '/\[boot\]/a command=/usr/local/bin/fix-mtu.sh' /etc/wsl.conf
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

# --- Pre-build zgenom plugin cache (avoids clone errors on first zsh login) ---
if [[ ! -f ~/.zgenom/init.zsh ]]; then
  echo "Pre-building zgenom plugin cache..."
  if [[ ! -d ~/.zgenom ]]; then
    GIT_TEMPLATE_DIR="" git clone https://github.com/jandamm/zgenom.git ~/.zgenom
  fi
  # Extract and run just the zgenom plugin block from .zshrc
  # GIT_TEMPLATE_DIR="" suppresses WSL git template copy errors that break clones
  GIT_TEMPLATE_DIR="" zsh -c '
    ZGEN_DIR="${HOME}/.zgenom"
    source "${ZGEN_DIR}/zgenom.zsh"
    zgenom ohmyzsh
    zgenom ohmyzsh plugins/sudo
    zgenom ohmyzsh plugins/colored-man-pages
    zgenom ohmyzsh plugins/extract
    zgenom ohmyzsh plugins/command-not-found
    zgenom ohmyzsh plugins/docker
    zgenom ohmyzsh plugins/docker-compose
    zgenom ohmyzsh plugins/npm
    zgenom ohmyzsh plugins/pip
    zgenom ohmyzsh plugins/dotnet
    zgenom load zdharma-continuum/fast-syntax-highlighting
    zgenom load zsh-users/zsh-autosuggestions
    zgenom load zsh-users/zsh-history-substring-search
    zgenom load zsh-users/zsh-completions
    zgenom load unixorn/fzf-zsh-plugin
    zgenom load Aloxaf/fzf-tab
    zgenom load romkatv/powerlevel10k powerlevel10k
    zgenom save
  '
fi

# --- Symlink Windows Claude settings (after stow to avoid path confusion) ---
WIN_USERPROFILE=$(cmd.exe /c "echo %USERPROFILE%" 2>/dev/null | tr -d '\r' | sed 's|\\|/|g' | sed 's|^\([A-Za-z]\):|/mnt/\L\1|')
if [[ -n "$WIN_USERPROFILE" && -d "$WIN_USERPROFILE/.claude" ]] && [[ ! -L ~/.claude ]]; then
  echo ""
  echo "Symlinking Windows Claude settings..."
  [[ -d ~/.claude ]] && mv ~/.claude ~/.claude.bak
  ln -s "$WIN_USERPROFILE/.claude" ~/.claude
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

# --- Configure git identity and SSH keys from GitHub ---
configure_github_identity() {
  local gh_cmd="$1"
  local gh_user gh_id gh_email

  gh_user=$($gh_cmd api user --jq '.login' 2>/dev/null) || return 1
  gh_id=$($gh_cmd api user --jq '.id' 2>/dev/null) || return 1
  gh_email="${gh_id}+${gh_user}@users.noreply.github.com"

  # Git identity (written to ~/.gitconfig.local, included by stowed .gitconfig)
  cat > ~/.gitconfig.local <<GITEOF
[user]
    name = ${gh_user}
    email = ${gh_email}
GITEOF

  # Allowed signers for SSH commit verification
  if [[ -f ~/.ssh/id_ed25519.pub ]]; then
    echo "${gh_email} $(cat ~/.ssh/id_ed25519.pub)" > ~/.ssh/allowed_signers
  fi

  # Register SSH key with GitHub
  $gh_cmd ssh-key add ~/.ssh/id_ed25519.pub --title "$(hostname) - WSL" --type authentication 2>/dev/null || true
  $gh_cmd ssh-key add ~/.ssh/id_ed25519.pub --type signing 2>/dev/null || true

  echo "  Git identity: ${gh_user} <${gh_email}>"
  echo "  SSH key registered with GitHub."
}

if ~/.local/bin/mise exec -- gh auth status &>/dev/null; then
  echo ""
  echo "Configuring GitHub identity..."
  configure_github_identity "$HOME/.local/bin/mise exec -- gh"
else
  # Plant a self-deleting login script for first interactive session
  echo ""
  echo "No GitHub token found — deferring GitHub setup to first login."
  mkdir -p ~/.zshrc.d
  cat > ~/.zshrc.d/fnwsl-gh-setup.zsh <<'GHEOF'
# fnwsl: one-time GitHub auth, git identity, and SSH key registration (self-deleting)
if [[ -t 0 ]] && command -v gh &>/dev/null; then
  _fnwsl_configure_and_register() {
    local gh_user gh_id gh_email
    gh_user=$(gh api user --jq '.login' 2>/dev/null) || return 1
    gh_id=$(gh api user --jq '.id' 2>/dev/null) || return 1
    gh_email="${gh_id}+${gh_user}@users.noreply.github.com"
    cat > ~/.gitconfig.local <<GITEOF
[user]
    name = ${gh_user}
    email = ${gh_email}
GITEOF
    if [[ -f ~/.ssh/id_ed25519.pub ]]; then
      echo "${gh_email} $(cat ~/.ssh/id_ed25519.pub)" > ~/.ssh/allowed_signers
    fi
    gh ssh-key add ~/.ssh/id_ed25519.pub --title "$(hostname) - WSL" --type authentication 2>/dev/null || true
    gh ssh-key add ~/.ssh/id_ed25519.pub --type signing 2>/dev/null || true
    echo "fnwsl: Git identity set to ${gh_user} <${gh_email}>"
    echo "fnwsl: SSH key registered with GitHub."
  }

  if gh auth status &>/dev/null; then
    _fnwsl_configure_and_register
  else
    echo ""
    echo "=== fnwsl: GitHub authentication ==="
    echo "Authenticate with GitHub to register your SSH key and configure git identity."
    echo ""
    if gh auth login; then
      _fnwsl_configure_and_register
    fi
  fi
  unfunction _fnwsl_configure_and_register
  rm -f ~/.zshrc.d/fnwsl-gh-setup.zsh
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
verify "SSH config symlink" "[[ -L ~/.ssh/config ]]"

# Git identity (only if gh was authed during install)
if [[ -f ~/.gitconfig.local ]]; then
  verify "git identity (.gitconfig.local)" "[[ -f ~/.gitconfig.local ]]"
  verify "SSH allowed_signers" "[[ -f ~/.ssh/allowed_signers ]]"
else
  echo "  SKIP  git identity (will be configured on first login)"
  echo "  SKIP  SSH allowed_signers (will be configured on first login)"
fi

# Dotfiles
verify ".zshrc symlink" "[[ -L ~/.zshrc ]]"
verify ".gitconfig symlink" "[[ -L ~/.gitconfig ]]"
verify ".tmux.conf symlink" "[[ -L ~/.tmux.conf ]]"
verify ".p10k.zsh" "[[ -f ~/.p10k.zsh ]]"

# wsl.conf
verify "wsl.conf hostname" "grep -q 'hostname=' /etc/wsl.conf"
verify "wsl.conf systemd" "grep -q 'systemd=true' /etc/wsl.conf"
verify "wsl.conf MTU boot cmd" "grep -q 'fix-mtu' /etc/wsl.conf"
verify "wsl.conf appendWindowsPath=false" "grep -q 'appendWindowsPath=false' /etc/wsl.conf"

# Networking
verify "IPv6 connectivity" "ip -6 addr show scope global 2>/dev/null | grep -q inet6"

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
echo "To allow inbound connections to WSL (SSH, HTTP servers, etc.):"
echo "  Set-NetFirewallHyperVVMSetting -Name '{40E0AC32-46A5-438A-A0B2-2B479E8F2E90}' -DefaultInboundAction Allow"
echo "  7. Install usbipd for ESP32/Pico USB passthrough:"
echo "       winget install dorssel.usbipd-win"
echo "  8. Attach USB device: usbipd bind --busid X-X && usbipd attach --wsl --busid X-X --auto-attach"
