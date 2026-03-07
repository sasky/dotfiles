#!/usr/bin/env bash
set -euo pipefail

# Usage: control-room
#        control-room stop
# Creates a tmux "control-room" session with 4 quarter panes for multi-project Claude work.
# Run from anywhere — attaches to existing session if already running.

SESSION="control-room"

if [[ "${1:-}" == "stop" ]]; then
  tmux kill-session -t "=$SESSION" 2>/dev/null && echo "Stopped session: $SESSION" || echo "No session: $SESSION"
  exit 0
fi

# Attach if session already exists
if tmux has-session -t "=$SESSION" 2>/dev/null; then
  exec tmux attach-session -t "=$SESSION"
fi

# Create session (pane 1 — top left)
tmux new-session -d -s "$SESSION" -c "$HOME" -x "$(tput cols)" -y "$(tput lines)"

# Split right (pane 2 — top right)
tmux split-window -h -t "$SESSION" -c "$HOME" -l 50%

# Split pane 1 down (bottom left) — right pane shifts from .2 to .3
tmux split-window -v -t "$SESSION:.1" -c "$HOME" -l 50%

# Split pane 3 down (bottom right) — .3 is the right pane now
tmux split-window -v -t "$SESSION:.3" -c "$HOME" -l 50%

# Override border colours for this session so format text is visible
tmux set-option -t "$SESSION" pane-border-style "fg=#ffffff"
tmux set-option -t "$SESSION" pane-active-border-style "fg=#5ef1ff"

# Show current path in pane borders (session-local, won't affect other sessions)
tmux set-option -t "$SESSION" pane-border-status top
tmux set-option -t "$SESSION" pane-border-format \
  '#{?pane_active,#[fg=#16181a,bg=#5ef1ff,bold],#[fg=#16181a,bg=#bd5eff,bold]} #{pane_index}: #(echo "#{pane_current_path}" | sed "s|$HOME|~|") '

# Focus top-left pane
tmux select-pane -t "$SESSION:.1"

exec tmux attach-session -t "$SESSION"
