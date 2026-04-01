#!/bin/bash
set -e

echo "=== fnwsl setup ==="

# --- System packages ---
sudo apt-get update
sudo apt-get install -y \
  zsh \
  keychain \
  fzf \
  stow \
  bat \
  fd-find \
  lsd \
  git \
  curl \
  wget

# --- Set zsh as default shell ---
if [[ "$SHELL" != */zsh ]]; then
  chsh -s /bin/zsh
  echo "Default shell changed to zsh. Will take effect on next login."
fi

# --- SSH key ---
if [[ ! -f ~/.ssh/id_ed25519 ]]; then
  echo ""
  echo "Generating SSH key..."
  ssh-keygen -t ed25519 -C "2511516+fnrhombus@users.noreply.github.com"
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

# --- Install Claude Code ---
if ! command -v claude &>/dev/null; then
  echo ""
  echo "Installing Claude Code..."
  curl -fsSL https://claude.ai/install.sh | bash
fi

# --- Symlink Windows Claude settings ---
if [[ -d /mnt/d/Users/Tom/.claude ]] && [[ ! -L ~/.claude ]]; then
  echo ""
  echo "Symlinking Windows Claude settings..."
  [[ -d ~/.claude ]] && mv ~/.claude ~/.claude.bak
  ln -s /mnt/d/Users/Tom/.claude ~/.claude
fi

# --- Stow dotfiles ---
echo ""
echo "Stowing dotfiles..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Back up existing files that would conflict
for f in ~/.zshrc ~/.zsh_aliases ~/.gitconfig; do
  if [[ -f "$f" && ! -L "$f" ]]; then
    mv "$f" "${f}.bak"
    echo "  Backed up $f → ${f}.bak"
  fi
done

stow --target="$HOME" zsh
stow --target="$HOME" git

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

# --- Powerlevel10k ---
echo ""
echo "=== Setup complete ==="
echo ""
echo "Next steps:"
echo "  1. Open a new zsh session (or run: exec zsh)"
echo "  2. Powerlevel10k will prompt you to configure your prompt"
echo "  3. If not logged into gh: run 'gh auth login'"
echo "  4. Verify git signing: git log --show-signature"
