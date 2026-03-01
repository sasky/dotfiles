# If you come from bash you might have to change your $PATH.
export PATH=$HOME/bin:/usr/local/bin:$PATH

# Setup for consistent global npm packages across nvm versions
export NPM_GLOBAL_DIR="$HOME/.npm-global"
[[ ! -d "$NPM_GLOBAL_DIR/bin" ]] && mkdir -p "$NPM_GLOBAL_DIR/bin"

# Add the hook for nvm to update npm config when node version changes
nvm_use_hook() {
  if [ -n "$NPM_GLOBAL_DIR" ]; then
    npm config set prefix "$NPM_GLOBAL_DIR"
  fi
}

export NVM_USE_HOOK=nvm_use_hook

# Add global npm bin to PATH
export PATH="$NPM_GLOBAL_DIR/bin:$PATH"
# Oh My Posh prompt
eval "$(oh-my-posh init zsh --config $(brew --prefix oh-my-posh)/themes/agnoster.omp.json)"

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
# for nvm apparently
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

# TMux dev session launcher
alias dev='~/.config/tmux/scripts/dev-session.sh'

alias ansinstall='sudo apt update && sudo apt install software-properties-common && sudo add-apt-repository --yes --update ppa:ansible/ansible && sudo apt install ansible'

# TODO: Replace nvm with a rust-based alternative (e.g. fnm) for faster shell startup
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# Auto-switch node version based on .nvmrc
autoload -U add-zsh-hook
load-nvmrc() {
  local nvmrc_path="$(nvm_find_nvmrc)"
  if [ -n "$nvmrc_path" ]; then
    local nvmrc_node_version=$(nvm version "$(cat "${nvmrc_path}")")
    if [ "$nvmrc_node_version" = "N/A" ]; then
      nvm install
    elif [ "$nvmrc_node_version" != "$(nvm version)" ]; then
      nvm use
    fi
  elif [ -n "$(PWD=$OLDPWD nvm_find_nvmrc)" ] && [ "$(nvm version)" != "$(nvm version default)" ]; then
    echo "Reverting to nvm default version"
    nvm use default
  fi
}
add-zsh-hook chpwd load-nvmrc
load-nvmrc

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
