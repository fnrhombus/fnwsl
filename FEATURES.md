# fnwsl Feature Selections

Cherry-picked from zsh-quickstart-kit and other sources. Each feature was individually reviewed.

## Plugins

| Feature | Status | Reason |
|---------|--------|--------|
| fast-syntax-highlighting | **IN** | Essential — catches typos before enter. User confirmed. |
| zsh-autosuggestions | **IN** | Essential — fish-like ghost suggestions from history. Auto-kept. |
| zsh-history-substring-search | **IN** | Essential — up/down arrow searches by what you've typed. Auto-kept. |
| zsh-completions | **IN** | Essential — extra tab completions for common tools. Auto-kept. |
| powerlevel10k | **IN** | Essential — fast prompt with instant prompt (no startup lag). Auto-kept. |
| fzf-zsh-plugin | **IN** | Ctrl+R fuzzy history, Ctrl+T file finder. User confirmed. |
| zsh-autocomplete | **COMMENTED** | Real-time completion dropdown. Commented out — noisy, conflicts with autosuggestions. Available if wanted. |
| zsh-you-should-use | **OUT** | Nudges you when you type a command that has an alias. Skipped — prints extra output. |
| Atuin | **OUT** | SQLite shell history with sync. Skipped — sync is the killer feature and user doesn't use multiple machines. |
| fzf-tab | **IN** | Replaces tab completion with fzf fuzzy picker. User confirmed. |
| zsh-defer | **OUT** | Defers plugin loading for instant startup. Skipped — plugin count is lean enough already. |
| lazygit | **OUT** | TUI git client. Skipped — user prefers vscode for git. |
| direnv | **IN** | Auto-loads env vars per directory via `.envrc` files. User confirmed. |
| jq | **IN** | JSON query/transform tool. User confirmed. |
| yq | **IN** | jq for YAML/TOML/XML. User confirmed. |
| xh | **IN** | Modern HTTP client with colored JSON output. User confirmed. |
| btop | **IN** | Beautiful system monitor (CPU, mem, net, disk). User confirmed. |
| yazi | **OUT** | TUI file manager. Skipped — redundant with eza/fzf/zoxide. |
| chezmoi | **OUT** | Dotfiles manager with templates. Skipped — single machine, stow works fine. |

## OMZ Plugins

| Feature | Status | Reason |
|---------|--------|--------|
| omz/sudo | **IN** | Esc-Esc to prepend sudo. No output, no cost. User confirmed. |
| omz/colored-man-pages | **IN** | Colorized man pages. Pure cosmetic, zero cost. User confirmed. |
| omz/git | **OUT** | ~150 git aliases (gst, gco, etc.). Skipped by user. |
| omz/extract | **IN** | One command to extract any archive format. User confirmed. |
| omz/command-not-found | **IN** | Suggests apt package when command not found. User confirmed. |
| omz/copypath | **OUT** | Copies current path to clipboard. Skipped — `pwd \| clip.exe` works fine. |
| omz/copyfile | **OUT** | Copies file contents to clipboard. Skipped — `cat file \| clip.exe` works fine. |
| omz/web-search | **OUT** | Open browser search from terminal. Skipped — clunky from WSL. |
| omz/docker | **IN** | Tab completion for Docker commands, containers, images. User confirmed. |
| omz/docker-compose | **IN** | Tab completion for docker-compose commands and services. User confirmed. |
| omz/aws | **OUT** | AWS CLI tab completion. Skipped — not actively using. |
| omz/kubectl | **OUT** | Kubernetes tab completion. Skipped — not doing k8s. |
| omz/terraform | **OUT** | Terraform tab completion. Skipped. |
| omz/python | **OUT** | Python aliases (pyfind, pyclean). Skipped — marginal value. |
| omz/pip | **OUT** | Pip tab completion. Skipped — uv/pipx preferred nowadays. |
| omz/node | **OUT** | Node helpers. Skipped — using mise instead. |
| omz/npm | **IN** | npm tab completion. Added back — mise manages versions, this provides completions. |
| zsh-nvm | **OUT** | Lazy-loads nvm. Skipped — using mise instead. |
| zsh-pyenv | **OUT** | Lazy-loads pyenv. Skipped — using mise instead. |

## Shell Settings

| Feature | Status | Reason |
|---------|--------|--------|
| AUTO_CD | **OUT** | Type directory name to cd into it. Skipped by user. |
| CORRECT | **OUT** | "Did you mean?" prompts on typos. Skipped — syntax highlighting covers this. |
| SHARE_HISTORY | **IN** | All terminal sessions share history in real time. User confirmed. |
| HIST_IGNORE_ALL_DUPS | **IN** | Essential — removes older duplicate entries from history. Auto-kept. |
| HISTSIZE=100000 | **IN** | Essential — large history file. Disk is cheap. Auto-kept. |
| HIST_IGNORE_SPACE | **IN** | Essential — prefix command with space to keep it out of history. Auto-kept. |
| HIST_REDUCE_BLANKS | **IN** | Essential — trims extra whitespace from history entries. Auto-kept. |
| HIST_SAVE_NO_DUPS | **IN** | Essential — no duplicates written to history file. Auto-kept. |
| HIST_EXPIRE_DUPS_FIRST | **IN** | Essential — when history is full, drop dupes first. Auto-kept. |
| HIST_FIND_NO_DUPS | **IN** | Essential — skip dupes when searching history. Auto-kept. |
| APPEND_HISTORY | **IN** | Essential — append to history file, don't overwrite. Auto-kept. |
| NO_BEEP | **IN** | Essential — no terminal bell. Auto-kept. |
| INTERACTIVE_COMMENTS | **IN** | Essential — allows # comments in interactive shell. Auto-kept. |
| MULTIOS | **IN** | Essential — allows multiple redirections. Auto-kept. |
| EXTENDED_GLOB | **OUT** | Power glob operators (^, #). Skipped — gotchas outweigh benefits. |
| sd | **IN** | Modern sed replacement with real regex. Installed via mise. User confirmed. |
| AUTO_PUSHD | **OUT** | Directory stack with cd. Skipped — cd -, Alt+C, typing paths covers this. |
| zmv | **OUT** | Batch rename with zsh patterns. Skipped — sd covers regex needs. |
| compinit caching | **IN** | Essential — only rebuild completions every 24h. Saves ~100-200ms per startup. Auto-kept. |
| Case-insensitive completion | **IN** | Essential — tab completion ignores case. Auto-kept. |
| REPORTTIME=2 | **IN** | Auto-prints duration for commands over 2 seconds. User confirmed. |
| typeset -aU path | **IN** | Essential — deduplicates PATH entries. Auto-kept. |

## Aliases & Functions

| Feature | Status | Reason |
|---------|--------|--------|
| `..`/`...`/`....` | **IN** | Navigation shortcuts. User confirmed. |
| ls cascading (eza > lsd > ls) | **IN** | Best ls replacement available, with fallback. User confirmed. |
| `grep --color=auto` | **IN** | Essential — highlight grep matches. Auto-kept. |
| `wget -c` | **IN** | Essential — always resume partial downloads. Auto-kept. |
| `myip` | **IN** | Prints public IP via curl. Auto-kept. |
| `gs` | **IN** | git status shortcut. User confirmed. |
| `mc()` | **IN** | mkdir + cd in one command. User confirmed. |
| `calc()` | **OUT** | Quick calculator via bc. Skipped. |
| keychain SSH agent | **IN** | Essential — one passphrase per reboot, persists across terminals. Auto-kept. |
| `~/.zshrc.d/` overrides | **IN** | Essential — drop-in local config without touching .zshrc. Auto-kept. |
| tmux auto-start | **OUT** | Auto-launch tmux on login. Skipped — annoying. |
| tmux | **IN** | Manual use for persistent sessions and Claude Code worktrees. User requested. |
| bat | **IN** | Essential — syntax-highlighted cat replacement. Already installed. Auto-kept. |
| fd | **IN** | Essential — modern find replacement, respects .gitignore. Already installed. Auto-kept. |
| ripgrep (rg) | **IN** | Essential — fast grep replacement, respects .gitignore. Auto-kept. |
| lsd | **IN** | ls replacement (fallback after eza). Already installed. Auto-kept. |
| mise | **IN** | Universal tool version manager. Replaces nvm/pyenv/rbenv. User requested. |
| zoxide | **IN** | Smart cd — learns your frequent directories. `z proj` jumps there. User confirmed. |
| delta | **OUT** | Better git diff in terminal. Skipped — user prefers vscode for diffs. |
| tldr | **IN** | Simplified, example-driven man pages. User confirmed. |
