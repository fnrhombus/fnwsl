# fnwsl

My WSL2 dotfiles. Lean zsh setup, cherry-picked one feature at a time.

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

If you've already cloned this repo:

```powershell
gsudo pwsh .\setup.ps1
```

It will ask for your WSL name, username, and passphrase, then do everything else non-interactively.

Or as a one-liner (download and run, no clone needed):

```powershell
iwr -Uri https://raw.githubusercontent.com/fnrhombus/fnwsl/main/setup.ps1 -OutFile $env:TEMP\fnwsl.ps1; gsudo pwsh $env:TEMP\fnwsl.ps1
```

From inside an existing WSL instance:

```bash
curl -fsSL https://raw.githubusercontent.com/fnrhombus/fnwsl/main/bootstrap.sh | bash -s -- "yourpassphrase"
exec zsh
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
