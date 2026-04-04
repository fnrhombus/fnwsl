# fnwsl

Opinionated, batteries-included WSL2 setup. One command gets you a fully configured dev environment with zsh, modern CLI tools, SSH, git signing, and sensible defaults.

## What's included

- **zsh** with zgenom plugin manager
- **Powerlevel10k** prompt (with instant prompt)
- **Syntax highlighting**, autosuggestions, history substring search
- **fzf** for Ctrl-R history search, Ctrl-T file finder, Alt-C directory jump
- **mise** for tool version management (node, python, etc.)
- **zoxide** smart cd — learns your frequent directories
- **tmux** for persistent sessions and worktrees
- **Modern CLI tools**: bat, fd, ripgrep, eza, lsd, sd, tldr
- **SSH** key management via keychain (one passphrase per reboot)
- **Git** config with SSH commit signing
- **Claude Code** install + Windows settings symlink

## Install

From an elevated PowerShell:

```powershell
irm https://github.com/fnrhombus/fnwsl/releases/latest/download/setup.ps1 | iex
```

Or from an elevated Command Prompt:

```cmd
pwsh -c "irm https://github.com/fnrhombus/fnwsl/releases/latest/download/setup.ps1 | iex"
```

It will ask for your WSL name, username, and passphrase, then do everything else non-interactively.

Fully unattended (all defaults, no prompts):

```powershell
irm https://github.com/fnrhombus/fnwsl/releases/latest/download/setup-forced.ps1 | iex
```

**Note:** The prompt uses [Powerlevel10k](https://github.com/romkatv/powerlevel10k) with a Nerd Font. If your terminal shows broken/missing glyphs, install a Nerd Font (e.g. [CaskaydiaCove](https://github.com/ryanoasis/nerd-fonts/releases/latest)). If you use oh-my-posh on Windows, the fonts are already there.

### Setup arguments

| Argument | Default | Description |
|----------|---------|-------------|
| `-WslName` | `{hostname}-wsl` | WSL distro name |
| `-WslUsername` | Current OS username | Linux username |
| `-Passphrase` | *(prompted)* | WSL password & SSH key passphrase (blank = none) |
| `-SetDefault` | `$true` | Set as default WSL distro |
| `-WslEnv` | *(prompted)* | Windows env vars to forward (e.g. `GH_TOKEN,GOPATH`) |
| `-P10kWizard` | off | Run Powerlevel10k config wizard instead of using defaults |
| `-Force` | off | Accept all defaults, skip all prompts |

```powershell
# Custom name and user
.\setup.ps1 -WslUsername tom -Passphrase "mypass" -WslName "dev-wsl"

# Forward env vars, no password
.\setup.ps1 -WslUsername tom -Passphrase "" -WslEnv GH_TOKEN,GOPATH
```

From inside an existing WSL instance:

```bash
curl -fsSL https://raw.githubusercontent.com/fnrhombus/fnwsl/main/bootstrap.sh | bash -s -- "yourpassphrase"
exec zsh
```

## Uninstall

From an elevated PowerShell:

```powershell
irm https://github.com/fnrhombus/fnwsl/releases/latest/download/unsetup.ps1 | iex
```

### Unsetup arguments

| Argument | Default | Description |
|----------|---------|-------------|
| `-WslName` | *(prompted)* | Instance to remove |
| `-Force` | off | Skip all prompts (requires `-WslName` if multiple instances) |
| `-KeepWslConfig` | off | Keep `.wslconfig` unchanged |
| `-RemoveWslConfig` | off | Force remove `.wslconfig` even if other instances exist |

```powershell
# Fully non-interactive
.\unsetup.ps1 -WslName "dev-wsl" -Force
```

## Structure

```
fnwsl/
  install.sh          # one-shot setup script
  zsh/
    .zshrc            # main config (stowed to ~)
    .zsh_aliases      # aliases (stowed to ~)
    .zshrc.d/         # drop-in overrides (stowed to ~)
  git/
    .gitconfig        # git config (stowed to ~)
  tmux/
    .tmux.conf        # tmux config (stowed to ~)
  ssh/
    config            # ssh config (symlinked to ~/.ssh/config)
  CHEATSHEET.md       # commands, shortcuts, and tips
  FEATURES.md         # every feature reviewed with rationale
```

## Plugins

| Plugin | What |
|--------|------|
| fast-syntax-highlighting | Highlights syntax errors as you type |
| zsh-autosuggestions | Fish-like inline suggestions from history |
| zsh-history-substring-search | Up/down arrow searches by what you've typed |
| zsh-completions | Extra tab completions |
| fzf-zsh-plugin | Ctrl-R fuzzy history search |
| powerlevel10k | Prompt theme with instant prompt |
| omz/sudo | Esc-Esc to prepend sudo |
| omz/colored-man-pages | Colorized man pages |
| omz/extract | One command to extract any archive |
| omz/command-not-found | Suggests apt package for unknown commands |
| omz/docker | Docker tab completions |
| omz/docker-compose | Docker Compose tab completions |

## Local overrides

Drop files in `~/.zshrc.d/` — they're sourced at the end of `.zshrc`.

## TODO

- [ ] Idempotent re-run / update path (update dotfiles and tools without full teardown)
