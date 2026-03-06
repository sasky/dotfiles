# If you come from bash you might have to change your $PATH.
export PATH=$HOME/bin:/usr/local/bin:$PATH

# Shared global npm packages across all node versions
export NPM_GLOBAL_DIR="$HOME/.npm-global"
[[ ! -d "$NPM_GLOBAL_DIR/bin" ]] && mkdir -p "$NPM_GLOBAL_DIR/bin"
export PATH="$NPM_GLOBAL_DIR/bin:$PATH"
# Oh My Posh prompt
eval "$(oh-my-posh init zsh --config ~/dotfiles/zsh/agnoster-custom.omp.json)"

# Zoxide (smarter cd)
eval "$(zoxide init zsh)"

export EDITOR='nvim'
# Compilation flags
# export ARCHFLAGS="-arch x86_64"

export PATH="/usr/local/opt/openssl@1.1/bin:$PATH"
export PATH="$HOME/.rbenv/bin:$PATH"
export PATH=/usr/local/bin:/usr/local/sbin:${PATH}
export PATH="$HOME/.local/bin:$PATH"

# Lines configured by zsh-newuser-install
HISTFILE=~/.histfile
HISTSIZE=1000
SAVEHIST=1000
unsetopt beep
# End of lines configured by zsh-newuser-install
# The following lines were added by compinstall
zstyle :compinstall filename '/Users/cam/.zshrc'

# Only regenerate compinit once per day
autoload -Uz compinit
if [[ -n ~/.zcompdump(#qN.mh+24) ]]; then
  compinit
else
  compinit -C
fi
# End of lines added by compinstall
# eval "$(nodenv init -)"
eval "$(rbenv init -)"
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh
alias ra='brew services restart httpd'
# https://stackoverflow.com/questions/33109315/unknown-unsupported-storage-engine-innodb
alias rmysql='brew services restart mariadb'
# Java

export JAVA_HOME=/Library/Java/JavaVirtualMachines/openjdk.jdk/Contents/Home
export SOLR_DATA_HOME=/Users/cam/Sites/iod/ss/.solr

# Vi mode for shell prompt (Esc=normal, i=insert)
bindkey -v
export KEYTIMEOUT=1  # 10ms Esc delay (default 400ms feels sluggish)

# Cursor shape: block=normal, beam=insert
zle-keymap-select() {
  if [[ $KEYMAP == vicmd ]]; then
    echo -ne '\e[2 q'  # block
  else
    echo -ne '\e[6 q'  # beam
  fi
}
zle -N zle-keymap-select
zle-line-init() { echo -ne '\e[6 q' }
zle -N zle-line-init

# alias ls='ls -F'
# alias ll='ls -alh'
alias vi='nvim'
alias e='xplr'
alias h='hx'
alias cat="bat"
alias l='eza'
alias la='eza -a'
alias ll='eza -lah'
alias ls='eza --color=auto'

alias gs='git status'
alias gc='git commit -m'
awake() {
  caffeinate -dims &
  local pid=$!
  trap "kill $pid 2>/dev/null; printf '\033[?25h\033[0m'; clear; echo 'Sleep prevention disabled.'; trap - INT" INT
  local cols=$(tput cols) lines=$(tput lines)
  printf '\033[2J\033[H\033[41;97;1m'
  for ((i=1; i<=lines; i++)); do printf "%${cols}s" ''; done
  local msg='STAYING  ALIVE'
  local sub='Press Ctrl+C to stop'
  printf '\033[%d;%dH%s' $((lines/2)) $(( (cols - ${#msg}) / 2 + 1 )) "$msg"
  printf '\033[%d;%dH%s' $((lines/2 + 2)) $(( (cols - ${#sub}) / 2 + 1 )) "$sub"
  printf '\033[?25l'
  wait $pid 2>/dev/null
  printf '\033[?25h\033[0m'; clear; trap - INT
}

# TMux dev session launcher
alias dev='~/.config/tmux/scripts/dev-session.sh'

alias ansinstall='sudo apt update && sudo apt install software-properties-common && sudo add-apt-repository --yes --update ppa:ansible/ansible && sudo apt install ansible'

# Node version manager (fnm - Rust-based, ~40x faster than nvm)
eval "$(fnm env --use-on-cd --shell zsh)"

if command -v pyenv 1>/dev/null 2>&1; then
  eval "$(pyenv init -)"
fi

# Cache brew prefix to avoid repeated subprocess calls
BREW_PREFIX="${BREW_PREFIX:-$(brew --prefix)}"
source "$BREW_PREFIX/share/google-cloud-sdk/path.zsh.inc"
source "$BREW_PREFIX/share/google-cloud-sdk/completion.zsh.inc"

# Generated for envman. Do not edit.
[ -s "$HOME/.config/envman/load.sh" ] && source "$HOME/.config/envman/load.sh"

# Added by Windsurf
export PATH="/Users/cam/.codeium/windsurf/bin:$PATH"

[[ "$TERM_PROGRAM" == "kiro" ]] && . "$(kiro --locate-shell-integration-path zsh)"

# Added by Antigravity
export PATH="/Users/cam/.antigravity/antigravity/bin:$PATH"
. "/Users/cam/.deno/env"
