# Brewfile — minimal migration set (terminal/tmux/nvim + core CLI).
# Deliberately excludes the old PHP/Apache/MariaDB stack — Docker replaces it.
# Undecided packages are listed in MIGRATION.md — decide there, then add here.
# Usage on new machine: brew bundle --file=~/dotfiles/Brewfile

tap "modem-dev/tap"

# Shell & terminal experience
brew "zsh"
brew "tmux"
brew "neovim"
brew "oh-my-posh"
brew "stow"
brew "fzf"
brew "zoxide"
brew "eza"
brew "bat"
brew "fd"
brew "ripgrep"
brew "jq"
brew "just"
brew "tree"
brew "wget"
brew "coreutils"
brew "gnu-sed"

# Git
brew "git"
brew "gh"
brew "lazygit"
brew "git-crypt"
brew "git-filter-repo"
brew "modem-dev/tap/hunk"

# Nvim ecosystem
brew "tree-sitter@0.25" # nvim-treesitter (main branch) needs the CLI

# Runtimes / version manager — see MIGRATION.md decision before installing
brew "mise"

# Services / misc
brew "syncthing" # after install: brew services start syncthing
brew "mkcert"
brew "rtk" # LLM token-saving CLI proxy — wired into Claude Code (PreToolUse hook + ~/.claude/RTK.md)

# Casks
cask "ghostty"
cask "claude-code"
# cask "orbstack"        # or "docker-desktop" — decide in MIGRATION.md
