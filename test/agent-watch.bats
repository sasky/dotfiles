#!/usr/bin/env bats
load helpers

setup() { common_setup; }

@test "help prints usage and exits 0" {
  run "$BIN" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"agent-watch"* ]]
  [[ "$output" == *"snapshot"* ]]
}

@test "unknown subcommand exits 1 with a message" {
  run "$BIN" bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown command"* ]]
}

# ── snapshot: state mapping ──────────────────────────────────────────────

@test "snapshot maps busy to working with empty detail" {
  session 101 busy "" "dev:@0.%1"
  pane %1 "✳ Fix the thing"
  run "$BIN" snapshot
  [ "$status" -eq 0 ]
  [ "$(jq -r '.[0].state' <<<"$output")" = "working" ]
  [ "$(jq -r '.[0].detail' <<<"$output")" = "" ]
}

@test "snapshot maps shell to working with background script detail" {
  session 101 shell "" "dev:@0.%1"
  pane %1 "✳ Fix the thing"
  run "$BIN" snapshot
  [ "$(jq -r '.[0].state' <<<"$output")" = "working" ]
  [ "$(jq -r '.[0].detail' <<<"$output")" = "background script" ]
}

@test "snapshot maps waiting to needs_you carrying waitingFor" {
  session 101 waiting "permission prompt" "dev:@0.%1"
  pane %1 "✳ Fix the thing"
  run "$BIN" snapshot
  [ "$(jq -r '.[0].state' <<<"$output")" = "needs_you" ]
  [ "$(jq -r '.[0].detail' <<<"$output")" = "permission prompt" ]
}

@test "snapshot maps waiting without waitingFor to needs input" {
  session 101 waiting "" "dev:@0.%1"
  pane %1 "✳ Fix the thing"
  run "$BIN" snapshot
  [ "$(jq -r '.[0].state' <<<"$output")" = "needs_you" ]
  [ "$(jq -r '.[0].detail' <<<"$output")" = "needs input" ]
}

@test "snapshot maps idle to ready" {
  session 101 idle "" "dev:@0.%1"
  pane %1 "✳ Fix the thing"
  run "$BIN" snapshot
  [ "$(jq -r '.[0].state' <<<"$output")" = "ready" ]
}

@test "snapshot shows an unknown status as working with the raw status as detail" {
  session 101 zzz "" "dev:@0.%1"
  pane %1 "✳ Fix the thing"
  run "$BIN" snapshot
  [ "$(jq -r '.[0].state' <<<"$output")" = "working" ]
  [ "$(jq -r '.[0].detail' <<<"$output")" = "zzz" ]
}

# ── snapshot: skips and fallbacks ────────────────────────────────────────

@test "snapshot skips a dead pid" {
  session 999 busy "" "dev:@0.%1"
  session 101 busy "" "dev:@0.%1"
  pane %1 "✳ Fix the thing"
  run "$BIN" snapshot
  [ "$(jq 'length' <<<"$output")" -eq 1 ]
  [ "$(jq -r '.[0].id' <<<"$output")" = "101" ]
}

@test "snapshot skips a truncated registry file and keeps the rest" {
  session 101 busy "" "dev:@0.%1"
  printf '{"pid": 102, "status": "bu' > "$AGENT_WATCH_SESSIONS_DIR/102.json"
  pane %1 "✳ Fix the thing"
  run "$BIN" snapshot
  [ "$status" -eq 0 ]
  [ "$(jq 'length' <<<"$output")" -eq 1 ]
}

@test "snapshot with no registry directory prints an empty array" {
  rm -rf "$AGENT_WATCH_SESSIONS_DIR"
  run "$BIN" snapshot
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "snapshot without a tmux field has null target and task falls back to name" {
  session 101 busy "" "" 1000000 "my-agent"
  run "$BIN" snapshot
  [ "$(jq -r '.[0].target' <<<"$output")" = "null" ]
  [ "$(jq -r '.[0].task' <<<"$output")" = "my-agent" ]
}

@test "snapshot whose pane is gone has null target" {
  session 101 busy "" "dev:@0.%1"
  run "$BIN" snapshot
  [ "$(jq -r '.[0].target' <<<"$output")" = "null" ]
}

# ── snapshot: task text and target ───────────────────────────────────────

@test "snapshot strips the leading glyph from the pane title" {
  session 101 busy "" "dev:@0.%1"
  pane %1 "✳ Money mindset phase 1"
  run "$BIN" snapshot
  [ "$(jq -r '.[0].task' <<<"$output")" = "Money mindset phase 1" ]
}

@test "snapshot keeps a title with no glyph as-is" {
  session 101 busy "" "dev:@0.%1"
  pane %1 "plain title"
  run "$BIN" snapshot
  [ "$(jq -r '.[0].task' <<<"$output")" = "plain title" ]
}

@test "snapshot falls back to name when the title is empty" {
  session 101 busy "" "dev:@0.%1" 1000000 "my-agent"
  pane %1 ""
  run "$BIN" snapshot
  [ "$(jq -r '.[0].task' <<<"$output")" = "my-agent" ]
}

@test "snapshot parses the tmux target including a session name with spaces" {
  session 101 busy "" "my project:@3.%7"
  pane %7 "✳ x"
  run "$BIN" snapshot
  [ "$(jq -r '.[0].target.session' <<<"$output")" = "my project" ]
  [ "$(jq -r '.[0].target.window' <<<"$output")" = "@3" ]
  [ "$(jq -r '.[0].target.pane' <<<"$output")" = "%7" ]
}

@test "snapshot carries id, session_id, name, cwd and since in seconds" {
  session 101 busy "" "dev:@0.%1" 1790739236790 "tsb-drupal-f4"
  pane %1 "✳ x"
  run "$BIN" snapshot
  [ "$(jq -r '.[0].provider' <<<"$output")" = "claude" ]
  [ "$(jq -r '.[0].id' <<<"$output")" = "101" ]
  [ "$(jq -r '.[0].session_id' <<<"$output")" = "sid-101" ]
  [ "$(jq -r '.[0].name' <<<"$output")" = "tsb-drupal-f4" ]
  [ "$(jq -r '.[0].cwd' <<<"$output")" = "/tmp/proj" ]
  [ "$(jq -r '.[0].since' <<<"$output")" = "1790739236" ]
}

# ── snapshot: seen-tracking ──────────────────────────────────────────────

@test "a ready agent with no seen record is unseen" {
  session 101 idle "" "dev:@0.%1" 5000000
  pane %1 "✳ x"
  run "$BIN" snapshot
  [ "$(jq -r '.[0].unseen' <<<"$output")" = "true" ]
}

@test "a ready agent seen before it went ready is unseen" {
  session 101 idle "" "dev:@0.%1" 5000000
  pane %1 "✳ x"
  echo '{"claude:101": 4000}' > "$AGENT_WATCH_STATE_DIR/seen.json"
  run "$BIN" snapshot
  [ "$(jq -r '.[0].unseen' <<<"$output")" = "true" ]
}

@test "a ready agent seen after it went ready is not unseen" {
  session 101 idle "" "dev:@0.%1" 5000000
  pane %1 "✳ x"
  echo '{"claude:101": 6000}' > "$AGENT_WATCH_STATE_DIR/seen.json"
  run "$BIN" snapshot
  [ "$(jq -r '.[0].unseen' <<<"$output")" = "false" ]
}

@test "a working agent is never unseen" {
  session 101 busy "" "dev:@0.%1" 5000000
  pane %1 "✳ x"
  run "$BIN" snapshot
  [ "$(jq -r '.[0].unseen' <<<"$output")" = "false" ]
}

@test "snapshot records a seen time when a client is on the agent's pane" {
  session 101 idle "" "dev:@0.%1" 5000000
  pane %1 "✳ x"
  client %1
  run "$BIN" snapshot
  [ "$(jq -r '.[0].unseen' <<<"$output")" = "false" ]
  seen=$(jq -r '."claude:101"' "$AGENT_WATCH_STATE_DIR/seen.json")
  [ "$seen" -gt 5000 ]
}

@test "snapshot keeps earlier seen times for agents not currently viewed" {
  session 101 idle "" "dev:@0.%1" 5000000
  session 102 idle "" "dev:@0.%2" 5000000
  pane %1 "✳ x"
  pane %2 "✳ y"
  echo '{"claude:102": 7000}' > "$AGENT_WATCH_STATE_DIR/seen.json"
  client %1
  run "$BIN" snapshot
  [ "$(jq -r '."claude:102"' "$AGENT_WATCH_STATE_DIR/seen.json")" = "7000" ]
}

@test "snapshot prunes seen entries for agents that are gone" {
  session 101 idle "" "dev:@0.%1" 5000000
  pane %1 "✳ x"
  echo '{"claude:101": 7000, "claude:555": 7000}' > "$AGENT_WATCH_STATE_DIR/seen.json"
  run "$BIN" snapshot
  [ "$(jq 'has("claude:555")' "$AGENT_WATCH_STATE_DIR/seen.json")" = "false" ]
}

# ── snapshot: sort order ─────────────────────────────────────────────────

@test "snapshot sorts needs_you, ready unseen, working, ready seen, oldest first within a group" {
  session 101 busy    "" "dev:@0.%1" 100000  "A-working"
  session 102 waiting "" "dev:@0.%2" 500000  "B-needs-late"
  session 103 waiting "" "dev:@0.%3" 200000  "C-needs-early"
  session 104 idle    "" "dev:@0.%4" 300000  "D-ready-unseen"
  session 105 idle    "" "dev:@0.%5" 50000   "E-ready-seen"
  for p in 1 2 3 4 5; do pane "%$p" "✳ t$p"; done
  echo '{"claude:105": 9000}' > "$AGENT_WATCH_STATE_DIR/seen.json"
  run "$BIN" snapshot
  [ "$(jq -r 'map(.name) | join(",")' <<<"$output")" = "C-needs-early,B-needs-late,D-ready-unseen,A-working,E-ready-seen" ]
}

# ── brief ────────────────────────────────────────────────────────────────

@test "brief prints nothing when there are no agents" {
  run "$BIN" brief
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "brief prints needs_you, ready, working counts in that order with colours" {
  session 101 waiting "" "dev:@0.%1"
  session 102 idle    "" "dev:@0.%2"
  session 103 busy    "" "dev:@0.%3"
  session 104 busy    "" "dev:@0.%4"
  for p in 1 2 3 4; do pane "%$p" "✳ t"; done
  run "$BIN" brief
  [ "$output" = "#[fg=#ff6e5e]● 1 #[fg=#5eff6c]● 1 #[fg=#5ef1ff]● 2#[fg=default]" ]
}

@test "brief omits empty states and dims ready when every ready agent is seen" {
  session 102 idle "" "dev:@0.%2" 5000000
  pane %2 "✳ t"
  echo '{"claude:102": 6000}' > "$AGENT_WATCH_STATE_DIR/seen.json"
  run "$BIN" brief
  [ "$output" = "#[fg=#3c4048]● 1#[fg=default]" ]
}
