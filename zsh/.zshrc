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
# Path to your oh-my-zsh installation.
export ZSH="/Users/cam/.oh-my-zsh"

# Set name of the theme to load --- if set to "random", it will
# load a random theme each time oh-my-zsh is loaded, in which case,
# to know which specific one was loaded, run: echo $RANDOM_THEME
# See https://github.com/ohmyzsh/ohmyzsh/wiki/Themes
ZSH_THEME="robbyrussell"
# ZSH_THEME="dstufft"

# Set list of themes to pick from when loading at random
# Setting this variable when ZSH_THEME=random will cause zsh to load
# a theme from this variable instead of looking in $ZSH/themes/
# If set to an empty array, this variable will have no effect.
# ZSH_THEME_RANDOM_CANDIDATES=( "robbyrussell" "agnoster" )

# Uncomment the following line to use case-sensitive completion.
# CASE_SENSITIVE="true"

# Uncomment the following line to use hyphen-insensitive completion.
# Case-sensitive completion must be off. _ and - will be interchangeable.
# HYPHEN_INSENSITIVE="true"

# Uncomment the following line to disable bi-weekly auto-update checks.
# DISABLE_AUTO_UPDATE="true"

# Uncomment the following line to automatically update without prompting.
# DISABLE_UPDATE_PROMPT="true"

# Uncomment the following line to change how often to auto-update (in days).
# export UPDATE_ZSH_DAYS=13

# Uncomment the following line if pasting URLs and other text is messed up.
# DISABLE_MAGIC_FUNCTIONS="true"

# Uncomment the following line to disable colors in ls.
# DISABLE_LS_COLORS="true"

# Uncomment the following line to disable auto-setting terminal title.
# DISABLE_AUTO_TITLE="true"

# Uncomment the following line to enable command auto-correction.
# ENABLE_CORRECTION="true"

# Uncomment the following line to display red dots whilst waiting for completion.
# Caution: this setting can cause issues with multiline prompts (zsh 5.7.1 and newer seem to work)
# See https://github.com/ohmyzsh/ohmyzsh/issues/5765
# COMPLETION_WAITING_DOTS="true"

# Uncomment the following line if you want to disable marking untracked files
# under VCS as dirty. This makes repository status check for large repositories
# much, much faster.
# DISABLE_UNTRACKED_FILES_DIRTY="true"

# Uncomment the following line if you want to change the command execution time
# stamp shown in the history command output.
# You can set one of the optional three formats:
# "mm/dd/yyyy"|"dd.mm.yyyy"|"yyyy-mm-dd"
# or set a custom format using the strftime function format specifications,
# see 'man strftime' for details.
# HIST_STAMPS="mm/dd/yyyy"

# Would you like to use another custom folder than $ZSH/custom?
# ZSH_CUSTOM=/path/to/new-custom-folder

# Which plugins would you like to load?
# Standard plugins can be found in $ZSH/plugins/
# Custom plugins may be added to $ZSH_CUSTOM/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
plugins=(
  git
  # zsh-vi-mode
  # zsh-autosuggestions
)

source $ZSH/oh-my-zsh.sh

# User configuration

# export MANPATH="/usr/local/man:$MANPATH"

# You may need to manually set your language environment
# export LANG=en_US.UTF-8
# Preferred editor for local and remote sessions
# if [[ -n $SSH_CONNECTION ]]; then
#   export EDITOR='vim'
# else
#   export EDITOR='mvim'
# fi

export EDITOR='nvim'
# Compilation flags
# export ARCHFLAGS="-arch x86_64"

# Set personal aliases, overriding those provided by oh-my-zsh libs,
# plugins, and themes. Aliases can be placed here, though oh-my-zsh
# users are encouraged to define aliases within the ZSH_CUSTOM folder.
# For a full list of active aliases, run `alias`.
#
# Example aliases
# alias zshconfig="mate ~/.zshrc"
# alias ohmyzsh="mate ~/.oh-my-zsh"
#
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

export NVM_DIR="$HOME/.nvm"

# Lazy-load nvm — defers ~390ms until first use of node/npm/nvm/npx
_load_nvm() {
  unset -f nvm node npm npx 2>/dev/null
  [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
  [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
}
nvm()  { _load_nvm; nvm "$@" }
node() { _load_nvm; node "$@" }
npm()  { _load_nvm; npm "$@" }
npx()  { _load_nvm; npx "$@" }

# Auto-switch node version based on .nvmrc (triggers lazy-load if needed)
autoload -U add-zsh-hook
load-nvmrc() {
  if ! type nvm_find_nvmrc &>/dev/null; then _load_nvm; fi
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
# Don't call load-nvmrc on startup — nvm loads lazily on first node/npm use

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
