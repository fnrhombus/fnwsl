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
  # --- Plugins (lean set — 7 plugins, not 25) ---
  zgenom ohmyzsh plugins/sudo             # Esc-Esc to prepend sudo
  zgenom ohmyzsh plugins/colored-man-pages # colorized man pages
  zgenom ohmyzsh plugins/git              # git aliases (gst, gco, gcmsg, etc.)

  zgenom load zdharma-continuum/fast-syntax-highlighting  # syntax errors as you type
  zgenom load zsh-users/zsh-autosuggestions               # fish-like inline suggestions
  zgenom load zsh-users/zsh-history-substring-search      # up/down searches by substring
  zgenom load zsh-users/zsh-completions                   # extra tab completions
  zgenom load unixorn/fzf-zsh-plugin                      # ctrl-r fzf history search

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
setopt AUTO_CD              # cd by typing directory name
setopt CORRECT              # suggest corrections for typos
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

# --- zmv (batch rename) ---
autoload -Uz zmv

# --- Deduplicate PATH ---
typeset -aU path

# --- SSH agent via keychain ---
eval $(keychain --eval --quiet --nogui ~/.ssh/id_ed25519)

# --- Aliases ---
source ~/.zsh_aliases 2>/dev/null

# --- Local overrides ---
for f in ~/.zshrc.d/*(N); do source "$f"; done

# --- Report slow commands ---
REPORTTIME=2

# --- Powerlevel10k config ---
[[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh
