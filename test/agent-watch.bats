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

# ── render ───────────────────────────────────────────────────────────────

@test "render with no agents prints header, no-agents line and footer" {
  run bash -c "echo '[]' | '$BIN' render --plain --width 34"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "AGENTS" ]
  [ "${lines[1]}" = "no agents" ]
  [ "${lines[2]}" = "C-a a jump · C-a b hide" ]
}

@test "render draws a four-line card with number, state, detail and age" {
  snap='[{"provider":"claude","id":"1","session_id":"s","name":"tsb-drupal-f4","cwd":"/x",
          "task":"Tmux side panel for AI agent progress","state":"needs_you","detail":"input needed",
          "since":1000,"unseen":false,"target":{"session":"dev","window":"@0","pane":"%1"}}]'
  run bash -c "echo '$snap' | '$BIN' render --plain --width 34 --now 1130"
  [ "${lines[0]}" = "1 needs you" ]
  [ "${lines[1]}" = "1 ● needs you · 2m · input" ]
  [ "${lines[2]}" = "  tsb-drupal-f4" ]
  [ "${lines[3]}" = "  Tmux side panel for AI agent" ]
  [ "${lines[4]}" = "  progress" ]
  [ "${lines[5]}" = "C-a a jump · C-a b hide" ]
}

@test "render omits the detail separator when detail is empty and formats ages" {
  snap='[{"provider":"claude","id":"1","session_id":"s","name":"a","cwd":"/x","task":"t",
          "state":"working","detail":"","since":1000,"unseen":false,"target":null},
         {"provider":"claude","id":"2","session_id":"s","name":"b","cwd":"/x","task":"t",
          "state":"ready","detail":"","since":0,"unseen":true,"target":null}]'
  run bash -c "echo '$snap' | '$BIN' render --plain --width 34 --now 1045"
  [ "${lines[0]}" = "1 ready · 1 working" ]
  [ "${lines[1]}" = "1 ● working · 45s" ]
  [ "${lines[4]}" = "2 ● ready · 17m" ]
}

@test "render truncates a long task to two lines with an ellipsis" {
  snap='[{"provider":"claude","id":"1","session_id":"s","name":"a","cwd":"/x",
          "task":"one two three four five six seven eight nine ten eleven twelve thirteen fourteen",
          "state":"working","detail":"","since":0,"unseen":false,"target":null}]'
  run bash -c "echo '$snap' | '$BIN' render --plain --width 34 --now 0"
  [ "${lines[3]}" = "  one two three four five six" ]
  [ "${lines[4]}" = "  seven eight nine ten eleven twe…" ]
  [ "${lines[5]}" = "C-a a jump · C-a b hide" ]
}

@test "render below 24 columns collapses cards to one line" {
  snap='[{"provider":"claude","id":"1","session_id":"s","name":"tsb-drupal-f4","cwd":"/x","task":"t",
          "state":"working","detail":"","since":0,"unseen":false,"target":null}]'
  run bash -c "echo '$snap' | '$BIN' render --plain --width 20 --now 0"
  [ "${lines[1]}" = "1 ● tsb-drupal-f4" ]
  [ "${lines[2]}" = "C-a a jump · C-a b …" ]
}

@test "render without --plain wraps lines in colour and clear-to-eol" {
  snap='[{"provider":"claude","id":"1","session_id":"s","name":"a","cwd":"/x","task":"t",
          "state":"needs_you","detail":"","since":0,"unseen":false,"target":null}]'
  run bash -c "echo '$snap' | '$BIN' render --width 34 --now 0 | sed -n 2p | /bin/cat -v"
  [[ "$output" == '^[[38;2;255;110;94m1 '* ]]
  [[ "$output" == *'^[[0m^[[K' ]]
}

# ── sidebar ──────────────────────────────────────────────────────────────

@test "sidebar --once marks its pane and draws a frame" {
  printf '34\t269\n' > "$FAKE_TMUX_DIR/display.out"
  run "$BIN" sidebar --once
  [ "$status" -eq 0 ]
  calls | grep -q '^set-option -p -t %9 @agent_watch_sidebar 1$'
  [[ "$output" == *"AGENTS"* ]]
  [[ "$output" == *"no agents"* ]]
}

@test "sidebar --once resizes its pane to the configured width in a wide window" {
  printf '80\t269\n' > "$FAKE_TMUX_DIR/display.out"
  run "$BIN" sidebar --once
  calls | grep -q '^resize-pane -t %9 -x 34$'
}

@test "sidebar --once does not resize when the window is 80 columns or narrower" {
  printf '20\t80\n' > "$FAKE_TMUX_DIR/display.out"
  run "$BIN" sidebar --once
  ! calls | grep -q '^resize-pane'
}

@test "sidebar --once does not resize when already at width" {
  printf '34\t269\n' > "$FAKE_TMUX_DIR/display.out"
  run "$BIN" sidebar --once
  ! calls | grep -q '^resize-pane'
}

@test "sidebar --once renders at the pane width tmux reports, not the terminal default" {
  printf '20\t60\n' > "$FAKE_TMUX_DIR/display.out"
  session 101 busy "" "dev:@0.%1" 1000000 "tsb-drupal-f4"
  pane %1 "✳ a long task title that would wrap"
  run "$BIN" sidebar --once
  [ "$status" -eq 0 ]
  [ "${lines[1]}" = "1 ● tsb-drupal-f4" ]
  [ "${lines[2]}" = "C-a a jump · C-a b …" ]
}

# ── menu ─────────────────────────────────────────────────────────────────

@test "menu with no agents shows a message instead of a menu" {
  run "$BIN" menu -c /dev/ttys001
  [ "$status" -eq 0 ]
  calls | grep -q '^display-message -c /dev/ttys001 agent-watch: no agents$'
  ! calls | grep -q '^display-menu'
}

@test "menu builds one row per agent with number keys and switch-client commands" {
  session 101 waiting "" "dev:@0.%1" 1000000 "alpha"
  session 102 busy    "" "dev:@0.%2" 1000000 "beta"
  pane %1 "✳ First task"
  pane %2 "✳ Second task"
  run "$BIN" menu -c /dev/ttys001
  [ "$status" -eq 0 ]
  line=$(calls | grep '^display-menu')
  [[ "$line" == "display-menu -c /dev/ttys001 -T  agents  -x C -y C "* ]]
  [[ "$line" == *"#[fg=#ff6e5e]●#[default] needs you  alpha · First task 1 switch-client -t '%1'"* ]]
  [[ "$line" == *"#[fg=#5ef1ff]●#[default] working  beta · Second task 2 switch-client -t '%2'"* ]]
}

@test "menu disables rows whose pane is gone" {
  session 101 busy "" "dev:@0.%1" 1000000 "alpha"
  run "$BIN" menu
  line=$(calls | grep '^display-menu')
  [[ "$line" == *"-#[fg=#5ef1ff]●#[default] working  alpha · alpha  "* ]]
}

@test "menu escapes # in task text and stops numbering after 9" {
  for i in 1 2 3 4 5 6 7 8 9 10; do
    session "$((100 + i))" busy "" "dev:@0.%$i" "$((1000000 * i))" "a$i"
    pane "%$i" "✳ issue #$i"
  done
  run "$BIN" menu
  line=$(calls | grep '^display-menu')
  [[ "$line" == *"a1 · issue ##1 1 switch-client -t '%1'"* ]]
  [[ "$line" == *"a9 · issue ##9 9 switch-client -t '%9'"* ]]
  [[ "$line" == *"a10 · issue ##10  switch-client -t '%10'"* ]]
}

# ── toggle / ensure ──────────────────────────────────────────────────────

@test "toggle opens a sidebar when the window has none and records on" {
  printf 'dev\t@0\t269\n' > "$FAKE_TMUX_DIR/display.out"
  printf '%%1\t\n%%2\t\n' > "$FAKE_TMUX_DIR/window-panes.tsv"
  run "$BIN" toggle -c /dev/ttys001
  [ "$status" -eq 0 ]
  calls | grep -q '^split-window -fh -l 34 -d -t @0 .*/bin/agent-watch sidebar$'
  calls | grep -q '^set-option -t dev @agent_watch on$'
  ! calls | grep -q '^kill-pane'
}

@test "toggle kills the sidebar when present and records off" {
  printf 'dev\t@0\t269\n' > "$FAKE_TMUX_DIR/display.out"
  printf '%%1\t\n%%5\t1\n' > "$FAKE_TMUX_DIR/window-panes.tsv"
  run "$BIN" toggle -c /dev/ttys001
  [ "$status" -eq 0 ]
  calls | grep -q '^kill-pane -t %5$'
  calls | grep -q '^set-option -t dev @agent_watch off$'
  ! calls | grep -q '^split-window'
}

@test "ensure opens a sidebar when absent" {
  printf 'dev\t@0\t269\n' > "$FAKE_TMUX_DIR/display.out"
  printf '%%1\t\n' > "$FAKE_TMUX_DIR/window-panes.tsv"
  run "$BIN" ensure -c /dev/ttys001
  [ "$status" -eq 0 ]
  calls | grep -q '^split-window'
}

@test "ensure does nothing when a sidebar is present" {
  printf 'dev\t@0\t269\n' > "$FAKE_TMUX_DIR/display.out"
  printf '%%1\t\n%%5\t1\n' > "$FAKE_TMUX_DIR/window-panes.tsv"
  run "$BIN" ensure -c /dev/ttys001
  ! calls | grep -q '^split-window'
  ! calls | grep -q '^kill-pane'
}

@test "ensure respects a session that toggled off" {
  printf 'dev\t@0\t269\n' > "$FAKE_TMUX_DIR/display.out"
  printf '%%1\t\n' > "$FAKE_TMUX_DIR/window-panes.tsv"
  printf 'off\n' > "$FAKE_TMUX_DIR/options.out"
  run "$BIN" ensure -c /dev/ttys001
  ! calls | grep -q '^split-window'
}

@test "toggle and ensure pass the client through to display-message" {
  printf 'dev\t@0\t269\n' > "$FAKE_TMUX_DIR/display.out"
  printf '%%1\t\n' > "$FAKE_TMUX_DIR/window-panes.tsv"
  run "$BIN" ensure -c /dev/ttys001
  calls | grep -q '^display-message -c /dev/ttys001 -p '
}

# ── fix pass: window lock ────────────────────────────────────────────────

@test "ensure does not split while another ensure holds the window lock" {
  printf 'dev\t@0\t269\n' > "$FAKE_TMUX_DIR/display.out"
  printf '%%1\t\n' > "$FAKE_TMUX_DIR/window-panes.tsv"
  mkdir -p "$AGENT_WATCH_STATE_DIR/locks/@0"
  run "$BIN" ensure -c /dev/ttys001
  [ "$status" -eq 0 ]
  ! calls | grep -q '^split-window'
}

@test "ensure breaks a stale window lock and splits" {
  printf 'dev\t@0\t269\n' > "$FAKE_TMUX_DIR/display.out"
  printf '%%1\t\n' > "$FAKE_TMUX_DIR/window-panes.tsv"
  mkdir -p "$AGENT_WATCH_STATE_DIR/locks/@0"
  touch -t 202001010000 "$AGENT_WATCH_STATE_DIR/locks/@0"
  run "$BIN" ensure -c /dev/ttys001
  calls | grep -q '^split-window'
  [ ! -d "$AGENT_WATCH_STATE_DIR/locks/@0" ]
}

@test "ensure releases the window lock after splitting" {
  printf 'dev\t@0\t269\n' > "$FAKE_TMUX_DIR/display.out"
  printf '%%1\t\n' > "$FAKE_TMUX_DIR/window-panes.tsv"
  run "$BIN" ensure -c /dev/ttys001
  calls | grep -q '^split-window'
  [ ! -d "$AGENT_WATCH_STATE_DIR/locks/@0" ]
}

@test "toggle does nothing while the window lock is held" {
  printf 'dev\t@0\t269\n' > "$FAKE_TMUX_DIR/display.out"
  printf '%%1\t\n%%5\t1\n' > "$FAKE_TMUX_DIR/window-panes.tsv"
  mkdir -p "$AGENT_WATCH_STATE_DIR/locks/@0"
  run "$BIN" toggle -c /dev/ttys001
  [ "$status" -eq 0 ]
  ! calls | grep -q '^kill-pane'
  ! calls | grep -q '^split-window'
}

# ── fix pass: menu name escaping ─────────────────────────────────────────

@test "menu escapes # in the session name" {
  session 101 busy "" "dev:@0.%1" 1000000 "fix #Sentry"
  pane %1 "✳ t"
  run "$BIN" menu
  line=$(calls | grep '^display-menu')
  [[ "$line" == *"working  fix ##Sentry · t 1 switch-client"* ]]
}

# ── fix pass: 34-column layout ───────────────────────────────────────────

@test "render header with all three states fits 34 columns" {
  snap='[{"provider":"claude","id":"1","session_id":"s","name":"a","cwd":"/x","task":"t","state":"needs_you","detail":"input needed","since":0,"unseen":false,"target":null},
         {"provider":"claude","id":"2","session_id":"s","name":"b","cwd":"/x","task":"t","state":"ready","detail":"","since":0,"unseen":true,"target":null},
         {"provider":"claude","id":"3","session_id":"s","name":"c","cwd":"/x","task":"t","state":"working","detail":"","since":0,"unseen":false,"target":null},
         {"provider":"claude","id":"4","session_id":"s","name":"d","cwd":"/x","task":"t","state":"working","detail":"","since":0,"unseen":false,"target":null}]'
  run bash -c "echo '$snap' | '$BIN' render --plain --width 34 --now 0"
  [ "${lines[0]}" = "1 needs you · 1 ready · 2 working" ]
}

@test "render keeps the age on a permission prompt card at 34 columns" {
  snap='[{"provider":"claude","id":"1","session_id":"s","name":"a","cwd":"/x","task":"t","state":"needs_you","detail":"permission prompt","since":1000,"unseen":false,"target":null}]'
  run bash -c "echo '$snap' | '$BIN' render --plain --width 34 --now 1130"
  [ "${lines[1]}" = "1 ● needs you · 2m · permission" ]
}

@test "render shortens background script and keeps the age" {
  snap='[{"provider":"claude","id":"1","session_id":"s","name":"a","cwd":"/x","task":"t","state":"working","detail":"background script","since":1000,"unseen":false,"target":null}]'
  run bash -c "echo '$snap' | '$BIN' render --plain --width 34 --now 1045"
  [ "${lines[1]}" = "1 ● working · 45s · bg script" ]
}

@test "render ends an over-long line with an ellipsis instead of a hard cut" {
  snap='[{"provider":"claude","id":"1","session_id":"s","name":"a","cwd":"/x","task":"t","state":"needs_you","detail":"permission prompt","since":1000,"unseen":false,"target":null}]'
  run bash -c "echo '$snap' | '$BIN' render --plain --width 24 --now 1130"
  [ "${lines[1]}" = "1 ● needs you · 2m · pe…" ]
}
