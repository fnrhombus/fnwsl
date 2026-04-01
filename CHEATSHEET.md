# fnwsl Cheatsheet

## Keyboard Shortcuts

| Shortcut | What it does | Source |
|----------|-------------|--------|
| **Ctrl+R** | Fuzzy search command history | fzf |
| **Ctrl+T** | Fuzzy find files in current directory | fzf |
| **Alt+C** | Fuzzy find and cd into a directory | fzf |
| **→** (right arrow) | Accept ghost suggestion | zsh-autosuggestions |
| **↑ / ↓** | Search history filtered by what you've typed | history-substring-search |
| **Tab** | Trigger tab completion | zsh-completions |
| **Esc Esc** | Prepend `sudo` to current/previous command | omz/sudo |

## Commands (from plugins)

| Command | What it does | Source |
|---------|-------------|--------|
| `extract <file>` | Extract any archive (tar, zip, 7z, rar, gz, bz2, xz, etc.) | omz/extract |
| `mc <dirname>` | Create a directory and cd into it | .zsh_aliases |

## File Tools

| Command | What it does |
|---------|-------------|
| `bat <file>` | Syntax-highlighted cat with line numbers and git diff markers |
| `fd <pattern>` | Find files by name (faster than `find`, respects .gitignore) |
| `fd -e js` | Find all .js files |
| `fd -e js pattern` | Find .js files matching pattern |
| `rg <pattern>` | Fast recursive grep (respects .gitignore) |
| `rg <pattern> -t js` | Grep only in .js files |
| `rg <pattern> -l` | List files containing matches (no content) |
| `tldr <command>` | Simplified man page with common examples |
| `btop` | System monitor (CPU, memory, network, disk, processes) |

## Data Tools

| Command | What it does |
|---------|-------------|
| `jq '.' file.json` | Pretty-print JSON |
| `jq '.key' file.json` | Extract a field |
| `jq '.items[].name' file.json` | Extract field from each array element |
| `curl api \| jq '.data'` | Pipe API response and extract data |
| `yq '.services' docker-compose.yml` | Query YAML files (same syntax as jq) |
| `yq -o json file.yaml` | Convert YAML to JSON |
| `xh get api.example.com/users` | HTTP GET with colored JSON output |
| `xh post api.example.com/data key=value` | HTTP POST with JSON body |
| `xh -d get url` | Download a file |

## Text Tools

| Command | What it does |
|---------|-------------|
| `sd 'pattern' 'replacement' file` | Regex find-and-replace in a file (modern sed) |
| `sd 'pattern' 'replacement'` | Same but reads from stdin (pipeable) |

## Aliases

| Alias | Expands to |
|-------|-----------|
| `..` / `...` / `....` | `cd ..` / `cd ../..` / `cd ../../..` |
| `ls` | `eza -F --icons` (or lsd, or plain ls) |
| `ll` | `eza -laF --icons --git` (long listing with git status) |
| `la` | `eza -aF --icons` (show hidden files) |
| `tree` | `eza --tree --icons` |
| `gs` | `git status` |
| `grep` | `grep --color=auto` |
| `wget` | `wget -c` (always resume) |
| `myip` | Print your public IP |

## Navigation

| Command | What it does | Source |
|---------|-------------|--------|
| `cd -` | Jump back to previous directory | built-in |
| `z <partial>` | Jump to a frequently used directory by partial name | zoxide |
| `zi` | Interactive directory picker (fzf-powered) | zoxide |
| **Alt+C** | Fuzzy find and cd into a directory | fzf |
| `..` | Alias for `cd ..` (if aliased) | .zsh_aliases |

## Shell Tricks

| Command | What it does |
|---------|-------------|
| ` command` (leading space) | Run a command without saving it to history |

## WSL Tips

| Command | What it does |
|---------|-------------|
| `pwd \| clip.exe` | Copy current directory path to Windows clipboard |
| `realpath <file> \| clip.exe` | Copy full file path to Windows clipboard |
| `cat <file> \| clip.exe` | Copy file contents to Windows clipboard |

## tmux

Prefix key is **Ctrl+a** (not the default Ctrl+b).

| Shortcut | What it does |
|----------|-------------|
| `tmux` | Start a new session |
| `tmux new -s name` | Start a named session |
| `tmux a` | Attach to last session |
| `tmux a -t name` | Attach to named session |
| `tmux ls` | List sessions |
| **Ctrl+a \|** | Split pane horizontally |
| **Ctrl+a -** | Split pane vertically |
| **Alt+arrow** | Switch between panes (no prefix needed) |
| **Ctrl+a c** | New window |
| **Ctrl+a 1-9** | Switch to window by number |
| **Ctrl+a d** | Detach from session |
| **Ctrl+a r** | Reload tmux config |
| **Ctrl+a [** | Enter scroll/copy mode (q to exit) |

## direnv (per-directory environment variables)

direnv automatically loads and unloads environment variables when you `cd` into
and out of directories. This keeps project-specific config isolated.

**How it works:**
1. You create a `.envrc` file in a project directory
2. You run `direnv allow` once (security gate — prevents untrusted repos from setting vars)
3. From then on, cd-ing into that directory loads the vars; cd-ing out unloads them

**Your shell will show a brief message** each time vars are loaded/unloaded — this is
intentional so you always know what's happening to your environment.

| Command | What it does |
|---------|-------------|
| `direnv allow` | Trust and activate the `.envrc` in the current directory |
| `direnv deny` | Block the `.envrc` in the current directory |
| `direnv edit .` | Open `.envrc` in your editor (auto-allows on save) |
| `direnv status` | Show current direnv state and loaded vars |

**Example `.envrc` files:**

```bash
# ESP-IDF project
export IDF_PATH=~/esp/esp-idf
source $IDF_PATH/export.sh

# Emscripten project
source ~/emsdk/emsdk_env.sh

# Node project (with mise)
use mise

# Simple env vars
export DATABASE_URL=postgres://localhost/mydb
export DEBUG=true
```

**Important:** Add `.envrc` to your global gitignore if it contains secrets.
Machine-specific `.envrc` files should NOT be committed to repos.

## mise

| Command | What it does |
|---------|-------------|
| `mise use node@20` | Install and use Node 20 in current project |
| `mise use -g node@20` | Install and set Node 20 globally |
| `mise ls` | List installed tools |
| `mise install` | Install tools from `.mise.toml` in current dir |

## Not Installed (add if needed)

| Feature | What it does | How to add |
|---------|-------------|------------|
| **zmv** | Batch rename files with patterns: `zmv '(*).txt' '$1.md'` | Add `autoload -Uz zmv` to `~/.zshrc.d/zmv.zsh` |
| **rename** | Batch rename files with regex: `rename 's/\.txt$/.md/' *.txt` | `sudo apt install rename` |
| **omz/git** | 150+ git aliases (gst, gco, gcmsg, gp, gl, etc.) | Add `zgenom ohmyzsh plugins/git` to .zshrc, run `zgenom reset` |
| **zsh-autocomplete** | Real-time completion dropdown as you type | Uncomment the line in .zshrc, run `zgenom reset` |
| **zsh-you-should-use** | Reminds you when you type a command that has an alias | Add `zgenom load MichaelAqwormed/zsh-you-should-use` to .zshrc, run `zgenom reset` |
| **Atuin** | SQLite shell history with cross-machine sync, exit codes, duration | `mise use -g atuin`, then `atuin init zsh` in .zshrc |
| **zsh-defer** | Defers plugin loading for instant startup | `zgenom load romkatv/zsh-defer` in .zshrc, wrap slow plugins with `zsh-defer source ...` |
| **lazygit** | Full-screen TUI git client (rebase, hunk staging, commit graph) | `mise use -g lazygit`, alias `lg=lazygit` |
| **yazi** | TUI file manager with image preview, Vim keybindings | `mise use -g yazi` |
| **chezmoi** | Dotfiles manager with templates (multi-machine) | `mise use -g chezmoi`, replaces stow |
| **delta** | Syntax-highlighted git diffs in terminal | `mise use -g delta`, add `[core] pager = delta` to .gitconfig |
