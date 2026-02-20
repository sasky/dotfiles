#!/usr/bin/env bash
set -euo pipefail

# Usage: dev <project-dir>
# Creates a tmux session with Claude Code, NVim, and a terminal pane.

DIR="${1:-.}"
DIR="$(cd "$DIR" && pwd)"
SESSION="$(basename "$DIR" | tr '.' '-')"

# Attach if session already exists
if tmux has-session -t "$SESSION" 2>/dev/null; then
  exec tmux attach-session -t "$SESSION"
fi

# Create session with first window, start Claude Code in left pane
tmux new-session -d -s "$SESSION" -c "$DIR" -x "$(tput cols)" -y "$(tput lines)"

# Left pane (pane 1): Claude Code — will be ~33% width
tmux send-keys -t "$SESSION" "claude" Enter

# Split right (pane 2): NVim — gets ~67% width
tmux split-window -h -t "$SESSION" -c "$DIR" -l 67%
tmux send-keys -t "$SESSION" "nvim" Enter

# Split bottom-right (pane 3): Terminal — 30% of right side height
tmux split-window -v -t "$SESSION" -c "$DIR" -l 30%

# Focus the NVim pane
tmux select-pane -t "$SESSION:.1"
tmux select-pane -t "$SESSION:.2"

exec tmux attach-session -t "$SESSION"
