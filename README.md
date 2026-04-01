# fnwsl

My WSL2 dotfiles. Lean zsh setup with 8 plugins instead of 38.

## What's included

- **zsh** with zgenom plugin manager
- **Powerlevel10k** prompt (with instant prompt)
- **Syntax highlighting**, autosuggestions, history substring search
- **fzf** for Ctrl-R history search
- **SSH** key management via keychain (one passphrase per reboot)
- **Git** config with SSH commit signing
- **Claude Code** install + Windows settings symlink

## Install

```bash
git clone https://github.com/fnrhombus/fnwsl ~/fnwsl
cd ~/fnwsl
chmod +x install.sh
./install.sh
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
  ssh/
    config            # ssh config (symlinked to ~/.ssh/config)
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
| omz/git | Git aliases (gst, gco, gcmsg, etc.) |

## Local overrides

Drop files in `~/.zshrc.d/` — they're sourced at the end of `.zshrc`.
