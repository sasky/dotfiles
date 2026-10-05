# shellcheck shell=bash
# shellcheck disable=SC2034  # BIN and FIX are consumed by agent-watch.bats
# Shared setup for test/agent-watch.bats. Loaded with `load helpers`.

common_setup() {
  BIN="$BATS_TEST_DIRNAME/../bin/agent-watch"
  FIX="$BATS_TEST_DIRNAME/fixtures/agent-watch"
  export AGENT_WATCH_SESSIONS_DIR="$BATS_TEST_TMPDIR/sessions"
  export AGENT_WATCH_STATE_DIR="$BATS_TEST_TMPDIR/state"
  export AGENT_WATCH_TMUX="$FIX/fake-tmux"
  export FAKE_TMUX_DIR="$BATS_TEST_TMPDIR/tmux"
  export AGENT_WATCH_ALIVE_PIDS="101 102 103 104 105 106 107 108 109 110 111 112"
  export TMUX_PANE="%9"
  mkdir -p "$AGENT_WATCH_SESSIONS_DIR" "$AGENT_WATCH_STATE_DIR" "$FAKE_TMUX_DIR"
  : > "$FAKE_TMUX_DIR/panes.tsv"
  : > "$FAKE_TMUX_DIR/window-panes.tsv"
  : > "$FAKE_TMUX_DIR/clients.txt"
  : > "$FAKE_TMUX_DIR/calls.log"
  : > "$FAKE_TMUX_DIR/display.out"
  : > "$FAKE_TMUX_DIR/options.out"
}

# session PID STATUS [WAITING_FOR] [TMUX_TARGET] [SINCE_MS] [NAME]
# Writes a registry file shaped like ~/.claude/sessions/<pid>.json.
session() {
  local pid="$1" status="$2" wf="${3:-}" tm="${4:-}" since="${5:-1000000}" name="${6:-agent-$1}"
  jq -n --argjson pid "$pid" --arg status "$status" --arg wf "$wf" --arg tm "$tm" \
    --argjson since "$since" --arg name "$name" '
    {pid: $pid, sessionId: "sid-\($pid)", cwd: "/tmp/proj", name: $name,
     status: $status, statusUpdatedAt: $since}
    + (if $tm != "" then {tmux: $tm} else {} end)
    + (if $wf != "" then {waitingFor: $wf} else {} end)' \
    > "$AGENT_WATCH_SESSIONS_DIR/$pid.json"
}

# pane PANE_ID TITLE   -> a pane the fake tmux reports for list-panes -a
pane() { printf '%s\t%s\n' "$1" "$2" >> "$FAKE_TMUX_DIR/panes.tsv"; }

# client PANE_ID       -> a client currently looking at PANE_ID
client() { printf '%s\n' "$1" >> "$FAKE_TMUX_DIR/clients.txt"; }

# calls                -> the fake tmux call log
calls() { cat "$FAKE_TMUX_DIR/calls.log"; }
