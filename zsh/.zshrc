# --- Powerlevel10k instant prompt (must be near top) ---
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# --- Zgenom plugin manager ---
ZGEN_DIR="${HOME}/.zgenom"
if [[ ! -d "$ZGEN_DIR" ]]; then
  git clone https://github.com/jandamm/zgenom.git "$ZGEN_DIR"
fi
source "${ZGEN_DIR}/zgenom.zsh"

if ! zgenom saved; then
  # --- Plugins ---
  zgenom ohmyzsh plugins/sudo             # Esc-Esc to prepend sudo
  zgenom ohmyzsh plugins/colored-man-pages # colorized man pages
  zgenom ohmyzsh plugins/extract          # `extract` any archive format
  zgenom ohmyzsh plugins/command-not-found # suggests apt package for unknown commands
  zgenom ohmyzsh plugins/docker           # docker tab completions
  zgenom ohmyzsh plugins/docker-compose   # docker-compose tab completions
  zgenom load zdharma-continuum/fast-syntax-highlighting  # syntax errors as you type
  zgenom load zsh-users/zsh-autosuggestions               # fish-like inline suggestions
  zgenom load zsh-users/zsh-history-substring-search      # up/down searches by substring
  zgenom load zsh-users/zsh-completions                   # extra tab completions
  zgenom load unixorn/fzf-zsh-plugin                      # ctrl-r fzf history search
  zgenom load Aloxaf/fzf-tab                              # fzf-powered tab completion

  # Uncomment for IDE-style completion dropdown as you type (shows options
  # from commands, paths, man pages — different from autosuggestions which
  # recalls history). Can feel noisy; needs config tuning with autosuggestions.
  # zgenom load marlonrichert/zsh-autocomplete              # real-time completion menu

  zgenom load romkatv/powerlevel10k powerlevel10k         # prompt/theme

  zgenom save
fi

# --- History ---
HISTFILE=~/.zsh_history
HISTSIZE=100000
SAVEHIST=100000
setopt APPEND_HISTORY
setopt SHARE_HISTORY
setopt HIST_EXPIRE_DUPS_FIRST
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_FIND_NO_DUPS
setopt HIST_IGNORE_SPACE
setopt HIST_SAVE_NO_DUPS
setopt HIST_REDUCE_BLANKS

# --- Shell options ---
setopt NO_BEEP
setopt INTERACTIVE_COMMENTS # allow # comments in interactive shell
setopt MULTIOS              # multiple redirections

# --- Completion ---
autoload -Uz compinit
if [[ -n ~/.zcompdump(#qN.mh+24) ]]; then
  compinit
else
  compinit -C  # use cache if less than 24h old
fi

zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path ~/.zsh/cache
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'  # case-insensitive

# --- Deduplicate PATH ---
typeset -aU path

# --- SSH agent via keychain ---
eval $(keychain --eval --quiet --nogui ~/.ssh/id_ed25519)

# --- mise (tool version manager) ---
eval "$(mise activate zsh)"

# --- zoxide (smart cd) ---
eval "$(zoxide init zsh)"

# --- direnv (per-directory environment variables) ---
# When you cd into a directory containing a .envrc file, direnv automatically
# loads the env vars defined in it. When you cd out, they're unloaded.
# This keeps project-specific vars (IDF_PATH, EMSCRIPTEN, NODE_ENV, etc.)
# isolated per project without polluting your global shell.
#
# Usage:
#   1. Create a .envrc in any project directory:
#      echo 'export MY_VAR=value' > .envrc
#   2. Allow it (required once per .envrc, security measure):
#      direnv allow
#   3. Now cd in/out and watch vars load/unload automatically.
#
# The "direnv allow" step is a security feature — it prevents untrusted
# repos from silently setting env vars when you clone and cd into them.
eval "$(direnv hook zsh)"

# --- Aliases ---
source ~/.zsh_aliases 2>/dev/null

# --- Local overrides ---
for f in ~/.zshrc.d/*(N); do source "$f"; done

# --- Report slow commands ---
REPORTTIME=2

# --- Powerlevel10k config ---
[[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh
