# agent-watch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A tmux sidebar, status-bar segment and jump menu that show every live Claude Code session as working, needs_you or ready, and jump to it.

**Architecture:** One bash script `bin/agent-watch` with a collector (`snapshot`) that reads Claude Code's live-session registry and tmux pane titles into sorted JSON, and three views (`sidebar`, `brief`, `menu`) plus tmux glue (`toggle`, `ensure`) that all consume that JSON. No daemon. tmux.conf wires two keys, two hooks and a status segment.

**Tech Stack:** bash 3.2 (macOS system bash), jq 1.8, tmux 3.7, bats-core for tests, shellcheck for lint.

**Spec:** `docs/superpowers/specs/2026-09-30-agent-watch-design.md`

## Global Constraints

- All code runs on `/bin/bash` 3.2.57: no associative arrays, no `mapfile`, no `${var,,}`, no `declare -n`, no `|&`.
- `bin/agent-watch` starts with `set -euo pipefail` and passes `shellcheck` with no warnings.
- Every external path or binary is overridable by environment variable: `AGENT_WATCH_SESSIONS_DIR`, `AGENT_WATCH_STATE_DIR`, `AGENT_WATCH_TMUX`, `AGENT_WATCH_ALIVE_PIDS`, `AGENT_WATCH_WIDTH`, `AGENT_WATCH_INTERVAL`.
- States are exactly `working`, `needs_you`, `ready`.
- Sort order: needs_you, ready unseen, working, ready seen; within a group `since` ascending.
- Colours: needs_you `#ff6e5e`, working `#5ef1ff`, ready unseen `#5eff6c`, ready seen and dim text `#3c4048`.
- Default sidebar width 34 columns; narrow layout below 24 columns; the sidebar only resizes its pane when the window is wider than 80 columns.
- Keys: `prefix + a` menu, `prefix + b` toggle. Session opt-out option `@agent_watch off`. Sidebar pane marker `@agent_watch_sidebar`.
- Commit after every task from `/Users/cam/dotfiles` with the sasky identity already configured there. Do not push.

## Review Focus

1. A pane title with no leading glyph, or an empty title: task text must be the title as-is, or fall back to the session name. Pinned in Task 2.
2. A registry file caught mid-write (truncated JSON): skipped this tick, never a crash or an empty snapshot. Pinned in Task 2.
3. A `waiting` status with no `waitingFor` field: detail must read "needs input", not be blank. Pinned in Task 2.
4. Task text or session name containing `#`: the menu label must escape it as `##` so tmux doesn't treat it as a format. Pinned in Task 7.
5. A window narrower than 80 columns (small laptop screen, or a zoomed split): the sidebar must not resize its pane, or it would fight the user. Pinned in Task 6.

---

### Task 1: Tooling, script skeleton, test harness

**Files:**
- Modify: `Brewfile`
- Create: `bin/agent-watch`
- Create: `test/agent-watch.bats`
- Create: `test/helpers.bash`
- Create: `test/fixtures/agent-watch/fake-tmux`

**Interfaces:**
- Produces: `bin/agent-watch <subcommand>` dispatch with `usage`, `die`, `need_jq`; the config variables `AW_SESSIONS_DIR`, `AW_STATE_DIR`, `AW_TMUX`, `AW_WIDTH`, `AW_INTERVAL`, `AW_SELF`; colour constants `C_NEED`, `C_WORK`, `C_READY_NEW`, `C_READY`, `C_DIM`; the test helpers `session`, `pane`, `client`, `calls`; and `fake-tmux`, which later tasks feed with fixture files.

- [ ] **Step 1: Add the two tools to the Brewfile and install them**

Open `Brewfile` and add, next to the other `brew` lines (keep them alphabetical if the file is):

```ruby
brew "bats-core"
brew "shellcheck"
```

Run: `cd /Users/cam/dotfiles && brew install bats-core shellcheck && bats --version && shellcheck --version | head -2`
Expected: both print a version.

- [ ] **Step 2: Write the fake tmux**

Create `test/fixtures/agent-watch/fake-tmux`:

```bash
#!/usr/bin/env bash
# Fake tmux for agent-watch tests.
# Logs every call to $FAKE_TMUX_DIR/calls.log and answers read-only queries
# from fixture files in $FAKE_TMUX_DIR:
#   list-panes -a      -> panes.tsv         (pane_id<TAB>pane_title)
#   list-panes -t ...  -> window-panes.tsv  (pane_id<TAB>marker)
#   list-clients       -> clients.txt       (one pane_id per line)
#   display-message -p -> display.out
#   show-options       -> options.out
# Every other command is logged and succeeds silently.
set -u
dir="${FAKE_TMUX_DIR:?FAKE_TMUX_DIR must be set}"
printf '%s\n' "$*" >> "$dir/calls.log"
case "${1:-}" in
  list-panes)
    if [ "${2:-}" = "-a" ]; then
      cat "$dir/panes.tsv" 2>/dev/null
    else
      cat "$dir/window-panes.tsv" 2>/dev/null
    fi
    ;;
  list-clients) cat "$dir/clients.txt" 2>/dev/null ;;
  display-message)
    case " $* " in *" -p "*) cat "$dir/display.out" 2>/dev/null ;; esac
    ;;
  show-options) cat "$dir/options.out" 2>/dev/null ;;
  *) : ;;
esac
exit 0
```

Run: `chmod +x test/fixtures/agent-watch/fake-tmux`

- [ ] **Step 3: Write the test helpers**

Create `test/helpers.bash`:

```bash
# shellcheck shell=bash
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
```

- [ ] **Step 4: Write the first failing tests**

Create `test/agent-watch.bats`:

```bash
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
```

- [ ] **Step 5: Run the tests to verify they fail**

Run: `cd /Users/cam/dotfiles && bats test/agent-watch.bats`
Expected: 2 failures, "No such file or directory" for `bin/agent-watch`.

- [ ] **Step 6: Write the script skeleton**

Create `bin/agent-watch`:

```bash
#!/usr/bin/env bash
# agent-watch — tmux sidebar, status segment and jump menu for AI agent sessions.
#
#   agent-watch snapshot          JSON array of live agents, sorted
#   agent-watch brief             one-line tmux status segment
#   agent-watch sidebar [--once]  run the sidebar in the current pane
#   agent-watch render [opts]     render a snapshot from stdin (used by sidebar and tests)
#   agent-watch menu [-c client]  jump menu
#   agent-watch toggle [-c client]
#   agent-watch ensure [-c client]
#
# See docs/agent-watch.md. Runs on bash 3.2; needs jq and tmux.
set -euo pipefail

# ── Config (all overridable) ─────────────────────────────────────────────
AW_SESSIONS_DIR="${AGENT_WATCH_SESSIONS_DIR:-$HOME/.claude/sessions}"
AW_STATE_DIR="${AGENT_WATCH_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/agent-watch}"
AW_TMUX="${AGENT_WATCH_TMUX:-tmux}"
AW_WIDTH="${AGENT_WATCH_WIDTH:-34}"
AW_INTERVAL="${AGENT_WATCH_INTERVAL:-2}"
AW_SELF="$(cd "$(dirname "$0")" && pwd -P)/$(basename "$0")"

C_NEED='#ff6e5e'      # needs_you
C_WORK='#5ef1ff'      # working
C_READY_NEW='#5eff6c' # ready, unseen
C_READY='#3c4048'     # ready, seen
C_DIM='#3c4048'

usage() {
  sed -n '2,/^set -euo/{ /^set -euo/d; s/^# \{0,1\}//; p; }' "$0"
}

die() { printf 'agent-watch: %s\n' "$*" >&2; exit 1; }

need_jq() { command -v jq >/dev/null 2>&1 || die "jq is required (brew install jq)"; }

# ── Dispatch ─────────────────────────────────────────────────────────────
main() {
  local cmd="${1:-}"
  [ $# -gt 0 ] && shift
  case "$cmd" in
    -h|--help|help|"") usage ;;
    *) die "unknown command: $cmd" ;;
  esac
}

need_jq
main "$@"
```

Run: `chmod +x bin/agent-watch`

- [ ] **Step 7: Run the tests to verify they pass**

Run: `bats test/agent-watch.bats && shellcheck bin/agent-watch test/fixtures/agent-watch/fake-tmux test/helpers.bash`
Expected: `2 tests, 0 failures`, shellcheck silent.

- [ ] **Step 8: Commit**

```bash
cd /Users/cam/dotfiles
git add Brewfile bin/agent-watch test/agent-watch.bats test/helpers.bash test/fixtures/agent-watch/fake-tmux
git commit -m "agent-watch: script skeleton, bats harness and fake tmux

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: Claude Code provider and `snapshot`

**Files:**
- Modify: `bin/agent-watch`
- Modify: `test/agent-watch.bats`

**Interfaces:**
- Consumes: config variables and helpers from Task 1.
- Produces: `cmd_snapshot` printing a JSON array of `{provider,id,session_id,name,cwd,task,state,detail,since,unseen,target}` sorted by state rank then `since`; `pid_alive PID`; `provider_claude` emitting raw JSON lines; `tmux_panes`; the shared jq prelude `AW_JQ_DEFS` with `parse_target`, `strip_glyph`, `map_state`, `rank`, `word`. Task 3 replaces the body of `cmd_snapshot` but keeps its name and output shape.

- [ ] **Step 1: Write the failing tests**

Append to `test/agent-watch.bats`:

```bash
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bats test/agent-watch.bats`
Expected: the new tests fail with "unknown command: snapshot".

- [ ] **Step 3: Implement the provider and collector**

In `bin/agent-watch`, insert this block between `need_jq()` and `# ── Dispatch`:

```bash
# ── Shared jq definitions ────────────────────────────────────────────────
# Prepended to every jq program so views and collector agree on the rules.
AW_JQ_DEFS='
  def parse_target:
    capture("^(?<session>[^:]+):(?<window>@[0-9]+)\\.(?<pane>%[0-9]+)$") // null;
  def strip_glyph: sub("^[^\\p{L}\\p{N}~/.]+"; "");
  def map_state:
    if   .raw_status == "busy"    then {state: "working",   detail: ""}
    elif .raw_status == "shell"   then {state: "working",   detail: "background script"}
    elif .raw_status == "waiting" then {state: "needs_you", detail: (if .waiting_for == "" then "needs input" else .waiting_for end)}
    elif .raw_status == "idle"    then {state: "ready",     detail: ""}
    else                               {state: "working",   detail: .raw_status} end;
  def rank:
    if .state == "needs_you" then 0
    elif .state == "ready" and .unseen then 1
    elif .state == "working" then 2
    else 3 end;
  def word: {needs_you: "needs you", working: "working", ready: "ready"}[.state];
'

# ── tmux queries ─────────────────────────────────────────────────────────
# pane_id<TAB>pane_title for every pane on the server; empty if no server.
TAB=$'\t'
tmux_panes() { "$AW_TMUX" list-panes -a -F "#{pane_id}${TAB}#{pane_title}" 2>/dev/null || true; }

# ── Providers ────────────────────────────────────────────────────────────
# A provider prints one raw JSON object per agent with the fields:
#   provider id session_id name cwd raw_status waiting_for since tmux
pid_alive() {
  if [ -n "${AGENT_WATCH_ALIVE_PIDS:-}" ]; then
    case " $AGENT_WATCH_ALIVE_PIDS " in *" $1 "*) return 0 ;; *) return 1 ;; esac
  fi
  kill -0 "$1" 2>/dev/null
}

provider_claude() {
  local f pid
  [ -d "$AW_SESSIONS_DIR" ] || return 0
  for f in "$AW_SESSIONS_DIR"/*.json; do
    [ -e "$f" ] || continue
    pid=$(jq -r '.pid // empty' "$f" 2>/dev/null) || continue
    [ -n "$pid" ] || continue
    pid_alive "$pid" || continue
    jq -c '{
      provider: "claude",
      id: (.pid | tostring),
      session_id: (.sessionId // ""),
      name: (.name // ("claude-" + (.pid | tostring))),
      cwd: (.cwd // ""),
      raw_status: (.status // "unknown"),
      waiting_for: (.waitingFor // ""),
      since: (((.statusUpdatedAt // .updatedAt // .startedAt // 0) / 1000) | floor),
      tmux: (.tmux // "")
    }' "$f" 2>/dev/null || true
  done
}

# ── Collector ────────────────────────────────────────────────────────────
cmd_snapshot() {
  local raw panes_json
  raw=$(provider_claude)
  panes_json=$(tmux_panes | jq -R -s -c '
    split("\n") | map(select(length > 0) | split("\t") | {key: .[0], value: (.[1] // "")}) | from_entries')
  printf '%s\n' "$raw" | jq -s -c --argjson panes "$panes_json" "$AW_JQ_DEFS"'
    map(
      (.tmux | parse_target) as $t
      | (if $t == null then false else ($panes | has($t.pane)) end) as $has_pane
      | (if $has_pane then ($panes[$t.pane] | strip_glyph) else "" end) as $title
      | map_state as $s
      | {provider, id, session_id, name, cwd,
         task: (if ($title | length) > 0 then $title else .name end),
         state: $s.state, detail: $s.detail, since,
         unseen: false,
         target: (if $has_pane then $t else null end)}
    )
    | sort_by(rank, .since)'
}
```

Add the `snapshot` case to `main`, above the `-h|--help` line:

```bash
    snapshot) cmd_snapshot "$@" ;;
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bats test/agent-watch.bats && shellcheck bin/agent-watch`
Expected: all pass, shellcheck silent.

- [ ] **Step 5: Sanity-check against the live registry**

Run: `unset AGENT_WATCH_SESSIONS_DIR AGENT_WATCH_TMUX AGENT_WATCH_ALIVE_PIDS; bin/agent-watch snapshot | jq -r '.[] | "\(.state)\t\(.name)\t\(.task)\t\(.target.pane)"'`
Expected: one line per running Claude session with a state, its name, its pane-title text and a `%N` pane id.

- [ ] **Step 6: Commit**

```bash
cd /Users/cam/dotfiles
git add bin/agent-watch test/agent-watch.bats
git commit -m "agent-watch: Claude Code provider and snapshot collector

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: Seen-tracking, unseen flag and full sort order

**Files:**
- Modify: `bin/agent-watch`
- Modify: `test/agent-watch.bats`

**Interfaces:**
- Consumes: `cmd_snapshot`, `AW_JQ_DEFS`, `tmux_panes` from Task 2.
- Produces: `cmd_snapshot` now sets `unseen` from the seen file and writes `$AW_STATE_DIR/seen.json` atomically; `tmux_client_panes` printing one pane id per attached client.

- [ ] **Step 1: Write the failing tests**

Append to `test/agent-watch.bats`:

```bash
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bats test/agent-watch.bats`
Expected: the seen-tracking tests fail on `unseen` being `false` or on the missing `seen.json`; the sort test fails because D-ready-unseen sorts last.

- [ ] **Step 3: Implement seen-tracking**

In `bin/agent-watch`, add below `tmux_panes`:

```bash
# One pane id per attached client: the pane each client is looking at now.
tmux_client_panes() { "$AW_TMUX" list-clients -F '#{pane_id}' 2>/dev/null || true; }
```

Replace the whole `cmd_snapshot` function with:

```bash
cmd_snapshot() {
  local raw panes_json clients_json now seen_file tmp out
  now=$(date +%s)
  mkdir -p "$AW_STATE_DIR"
  seen_file="$AW_STATE_DIR/seen.json"
  # Our own file, but reset it rather than fail if it was ever left corrupt.
  jq -e 'type == "object"' "$seen_file" >/dev/null 2>&1 || printf '{}\n' > "$seen_file"

  raw=$(provider_claude)
  panes_json=$(tmux_panes | jq -R -s -c '
    split("\n") | map(select(length > 0) | split("\t") | {key: .[0], value: (.[1] // "")}) | from_entries')
  clients_json=$(tmux_client_panes | jq -R -s -c 'split("\n") | map(select(length > 0))')

  out=$(printf '%s\n' "$raw" | jq -s -c \
    --argjson now "$now" --argjson panes "$panes_json" --argjson clients "$clients_json" \
    --slurpfile seenfile "$seen_file" "$AW_JQ_DEFS"'
    ($seenfile[0] // {}) as $seen0
    | map(
        (.tmux | parse_target) as $t
        | (if $t == null then false else ($panes | has($t.pane)) end) as $has_pane
        | (if $has_pane then ($panes[$t.pane] | strip_glyph) else "" end) as $title
        | map_state as $s
        | "\(.provider):\(.id)" as $key
        | (if $has_pane then (($clients | index($t.pane)) != null) else false end) as $viewed
        | (if $viewed then $now else ($seen0[$key] // null) end) as $seen_at
        | {provider, id, session_id, name, cwd,
           task: (if ($title | length) > 0 then $title else .name end),
           state: $s.state, detail: $s.detail, since,
           unseen: ($s.state == "ready" and ($seen_at == null or $seen_at < .since)),
           target: (if $has_pane then $t else null end),
           _key: $key, _seen: $seen_at}
      )
    | { seen: (map(select(._seen != null) | {key: ._key, value: ._seen}) | from_entries),
        snapshot: (map(del(._key, ._seen)) | sort_by(rank, .since)) }')

  tmp=$(mktemp "$AW_STATE_DIR/seen.XXXXXX")
  printf '%s\n' "$out" | jq -c '.seen' > "$tmp" && mv "$tmp" "$seen_file"
  printf '%s\n' "$out" | jq -c '.snapshot'
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bats test/agent-watch.bats && shellcheck bin/agent-watch`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
cd /Users/cam/dotfiles
git add bin/agent-watch test/agent-watch.bats
git commit -m "agent-watch: seen-tracking, unseen flag and full sort order

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4: Status-bar segment `brief`

**Files:**
- Modify: `bin/agent-watch`
- Modify: `test/agent-watch.bats`

**Interfaces:**
- Consumes: `cmd_snapshot`, colour constants.
- Produces: `cmd_brief` printing one line of tmux format text, or nothing.

- [ ] **Step 1: Write the failing tests**

Append to `test/agent-watch.bats`:

```bash
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bats test/agent-watch.bats`
Expected: the three brief tests fail with "unknown command: brief".

- [ ] **Step 3: Implement brief**

In `bin/agent-watch`, add after `cmd_snapshot`:

```bash
# ── Views ────────────────────────────────────────────────────────────────
cmd_brief() {
  cmd_snapshot | jq -r \
    --arg need "$C_NEED" --arg work "$C_WORK" --arg rnew "$C_READY_NEW" --arg rold "$C_READY" '
    def seg(c; n): "#[fg=\(c)]● \(n)";
    (map(select(.state == "needs_you")) | length) as $n
    | (map(select(.state == "ready" and .unseen)) | length) as $ru
    | (map(select(.state == "ready" and (.unseen | not))) | length) as $rs
    | (map(select(.state == "working")) | length) as $w
    | [ (if $n > 0 then seg($need; $n) else empty end),
        (if ($ru + $rs) > 0 then seg((if $ru > 0 then $rnew else $rold end); $ru + $rs) else empty end),
        (if $w > 0 then seg($work; $w) else empty end) ]
    | if length == 0 then "" else join(" ") + "#[fg=default]" end'
}
```

Add to `main`:

```bash
    brief) cmd_brief "$@" ;;
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bats test/agent-watch.bats && shellcheck bin/agent-watch`
Expected: all pass. Note: `jq -r` of an empty string prints an empty line; bats `$output` strips it, and tmux shows an empty segment.

- [ ] **Step 5: Commit**

```bash
cd /Users/cam/dotfiles
git add bin/agent-watch test/agent-watch.bats
git commit -m "agent-watch: brief status-bar segment

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 5: Card renderer `render`

**Files:**
- Modify: `bin/agent-watch`
- Modify: `test/agent-watch.bats`

**Interfaces:**
- Consumes: snapshot JSON on stdin; `AW_JQ_DEFS` (`word`), colour constants.
- Produces: `cmd_render [--width N] [--plain] [--now EPOCH]` printing the sidebar frame, one line per output row. Without `--plain`, each line is wrapped in a truecolor SGR and ends with clear-to-end-of-line. `sgr_hex '#rrggbb'` helper. Task 6 loops around this.

- [ ] **Step 1: Write the failing tests**

Append to `test/agent-watch.bats`:

```bash
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
  [ "${lines[0]}" = "AGENTS  1 needs you" ]
  [ "${lines[1]}" = "1 ● needs you · input needed · 2m" ]
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
  [ "${lines[0]}" = "AGENTS  1 ready · 1 working" ]
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
  [ "${lines[2]}" = "C-a a jump · C-a b h" ]
}

@test "render without --plain wraps lines in colour and clear-to-eol" {
  snap='[{"provider":"claude","id":"1","session_id":"s","name":"a","cwd":"/x","task":"t",
          "state":"needs_you","detail":"","since":0,"unseen":false,"target":null}]'
  run bash -c "echo '$snap' | '$BIN' render --width 34 --now 0 | sed -n 2p | /bin/cat -v"
  [[ "$output" == '^[[38;2;255;110;94m1 '* ]]
  [[ "$output" == *'^[[0m^[[K' ]]
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bats test/agent-watch.bats`
Expected: the render tests fail with "unknown command: render".

- [ ] **Step 3: Implement render**

In `bin/agent-watch`, add after `cmd_brief`:

```bash
# '#rrggbb' -> truecolor foreground SGR
sgr_hex() {
  local h="${1#\#}"
  printf '\033[38;2;%d;%d;%dm' "0x${h:0:2}" "0x${h:2:2}" "0x${h:4:2}"
}

# kind -> SGR prefix for a rendered line
sgr_kind() {
  case "$1" in
    need) sgr_hex "$C_NEED" ;;
    work) sgr_hex "$C_WORK" ;;
    rnew) sgr_hex "$C_READY_NEW" ;;
    rold) sgr_hex "$C_READY" ;;
    dim)  sgr_hex "$C_DIM" ;;
    head) printf '\033[1m' ;;
    *)    : ;;
  esac
}

# render [--width N] [--plain] [--now EPOCH]  (snapshot JSON on stdin)
cmd_render() {
  local w="$AW_WIDTH" plain=0 now kind text
  now=$(date +%s)
  while [ $# -gt 0 ]; do
    case "$1" in
      --width) w="$2"; shift 2 ;;
      --plain) plain=1; shift ;;
      --now)   now="$2"; shift 2 ;;
      *) die "render: unknown option $1" ;;
    esac
  done
  jq -r --argjson w "$w" --argjson now "$now" "$AW_JQ_DEFS"'
    def ago:
      ([$now - .since, 0] | max) as $d
      | if $d < 60 then "\($d)s"
        elif $d < 3600 then "\($d / 60 | floor)m"
        else "\($d / 3600 | floor)h\((($d % 3600) / 60) | floor)m" end;
    def kind:
      if .state == "needs_you" then "need"
      elif .state == "working" then "work"
      elif .unseen then "rnew" else "rold" end;
    def clip($n): if length > $n then .[0:$n - 1] + "…" else . end;
    def wrap($n):
      (split(" ") | reduce .[] as $wd ([""];
        if (.[-1] | length) == 0 then .[:-1] + [$wd]
        elif ((.[-1] | length) + 1 + ($wd | length)) <= $n then .[:-1] + [.[-1] + " " + $wd]
        else . + [$wd] end)) | map(clip($n));
    def two_lines($n):
      wrap($n) as $ls
      | if ($ls | length) > 2 then [$ls[0], (($ls[1:] | join(" ")) | .[0:$n - 1] + "…")] else $ls end;
    (map(select(.state == "needs_you")) | length) as $n
    | (map(select(.state == "ready")) | length) as $r
    | (map(select(.state == "working")) | length) as $wk
    | ([ (if $n > 0 then "\($n) needs you" else empty end),
         (if $r > 0 then "\($r) ready" else empty end),
         (if $wk > 0 then "\($wk) working" else empty end) ] | join(" · ")) as $counts
    | ["head\tAGENTS" + (if $counts == "" then "" else "  " + $counts end)]
      + (if length == 0 then ["dim\tno agents"]
         elif $w < 24 then [ to_entries[] | "\(.value | kind)\t\(.key + 1) ● \(.value.name)" ]
         else [ to_entries[] | .key as $i | .value
                | "\(kind)\t\($i + 1) ● \(word)\(if .detail != "" then " · " + .detail else "" end) · \(ago)",
                  "plain\t  \(.name)",
                  (.task | two_lines($w - 2) | .[] | "dim\t  " + .) ]
         end)
      + ["dim\tC-a a jump · C-a b hide"]
    | .[]
    | (split("\t") | .[0] + "\t" + (.[1] | .[0:$w]))' \
  | while IFS=$'\t' read -r kind text; do
      if [ "$plain" = 1 ]; then
        printf '%s\n' "$text"
      else
        printf '%s%s\033[0m\033[K\n' "$(sgr_kind "$kind")" "$text"
      fi
    done
}
```

Add to `main`:

```bash
    render) cmd_render "$@" ;;
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bats test/agent-watch.bats && shellcheck bin/agent-watch`
Expected: all pass. If the truncation test differs by one character, the `clip` boundary is off: `.[0:$n - 1] + "…"` must yield exactly `$n` characters.

- [ ] **Step 5: Commit**

```bash
cd /Users/cam/dotfiles
git add bin/agent-watch test/agent-watch.bats
git commit -m "agent-watch: card renderer

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 6: Sidebar loop `sidebar`

**Files:**
- Modify: `bin/agent-watch`
- Modify: `test/agent-watch.bats`

**Interfaces:**
- Consumes: `cmd_snapshot`, `cmd_render`, `AW_WIDTH`, `AW_INTERVAL`, `AW_TMUX`, `TMUX_PANE`.
- Produces: `cmd_sidebar [--once]`; `fix_width`. Marks its pane with `@agent_watch_sidebar 1`, which Task 8 searches for.

- [ ] **Step 1: Write the failing tests**

Append to `test/agent-watch.bats`:

```bash
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bats test/agent-watch.bats`
Expected: the sidebar tests fail with "unknown command: sidebar".

- [ ] **Step 3: Implement the sidebar loop**

In `bin/agent-watch`, add after `cmd_render`:

```bash
# Keep the sidebar pane at AW_WIDTH, but only when the window is wide enough
# that a fixed-width pane can't fight the user for space.
fix_width() {
  [ -n "${TMUX_PANE:-}" ] || return 0
  local out pw ww
  out=$("$AW_TMUX" display-message -p -t "$TMUX_PANE" "#{pane_width}${TAB}#{window_width}" 2>/dev/null) || return 0
  IFS="$TAB" read -r pw ww <<<"$out"
  [ -n "${pw:-}" ] && [ -n "${ww:-}" ] || return 0
  if [ "$pw" != "$AW_WIDTH" ] && [ "$ww" -gt 80 ]; then
    "$AW_TMUX" resize-pane -t "$TMUX_PANE" -x "$AW_WIDTH" 2>/dev/null || true
  fi
}

# sidebar [--once]   run inside a tmux pane; --once draws one frame and exits
cmd_sidebar() {
  local once=0 cols sleep_pid=""
  [ "${1:-}" = "--once" ] && once=1
  if [ -n "${TMUX_PANE:-}" ]; then
    "$AW_TMUX" set-option -p -t "$TMUX_PANE" @agent_watch_sidebar 1 2>/dev/null || true
  fi
  if [ "$once" = 0 ]; then
    trap 'printf "\033[?25h\033[0m"' EXIT
    trap 'exit 0' INT TERM HUP
    trap 'kill "${sleep_pid:-}" 2>/dev/null || true' WINCH
    printf '\033[?25l'
  fi
  while :; do
    fix_width
    cols=$(tput cols 2>/dev/null || printf '%s' "$AW_WIDTH")
    [ "$once" = 0 ] && printf '\033[H'
    if [ "$once" = 1 ]; then
      cmd_snapshot | cmd_render --plain --width "$cols"
      break
    fi
    cmd_snapshot | cmd_render --width "$cols"
    printf '\033[J'
    sleep "$AW_INTERVAL" &
    sleep_pid=$!
    wait "$sleep_pid" 2>/dev/null || true
  done
}
```

Add to `main`:

```bash
    sidebar) cmd_sidebar "$@" ;;
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bats test/agent-watch.bats && shellcheck bin/agent-watch`
Expected: all pass.

- [ ] **Step 5: Try it live in a throwaway pane**

Run in your current tmux window: `tmux split-window -fh -l 34 -d "$PWD/bin/agent-watch sidebar"`
Expected: a right-hand pane appears with a card per running Claude session, refreshing every two seconds, in colour. Then close it: `tmux kill-pane -t "$(tmux list-panes -F '#{pane_id} #{@agent_watch_sidebar}' | awk '$2==1{print $1}')"`.

- [ ] **Step 6: Commit**

```bash
cd /Users/cam/dotfiles
git add bin/agent-watch test/agent-watch.bats
git commit -m "agent-watch: sidebar loop with pane marker and width fix

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 7: Jump menu `menu`

**Files:**
- Modify: `bin/agent-watch`
- Modify: `test/agent-watch.bats`

**Interfaces:**
- Consumes: `cmd_snapshot`, `AW_JQ_DEFS` (`word`), colour constants.
- Produces: `cmd_menu [-c client]`; `parse_client` setting `CLIENT`; `tmux_c CMD ARGS...` which inserts `-c "$CLIENT"` when set. Task 8 reuses `parse_client` and `tmux_c`.

- [ ] **Step 1: Write the failing tests**

Append to `test/agent-watch.bats`:

```bash
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bats test/agent-watch.bats`
Expected: the menu tests fail with "unknown command: menu".

- [ ] **Step 3: Implement the menu**

In `bin/agent-watch`, add after `cmd_sidebar`:

```bash
# ── tmux glue ────────────────────────────────────────────────────────────
CLIENT=""

# parse_client ARGS...   sets CLIENT from -c <client>, ignores anything else
parse_client() {
  CLIENT=""
  while [ $# -gt 0 ]; do
    case "$1" in
      -c) CLIENT="${2:-}"; shift 2 ;;
      *) shift ;;
    esac
  done
}

# tmux_c SUBCOMMAND ARGS...   runs tmux with -c "$CLIENT" inserted when set
tmux_c() {
  local sub="$1"
  shift
  if [ -n "$CLIENT" ]; then
    "$AW_TMUX" "$sub" -c "$CLIENT" "$@"
  else
    "$AW_TMUX" "$sub" "$@"
  fi
}

# menu [-c client]   display-menu of agents; number keys jump
cmd_menu() {
  local snap label key cmd
  local -a args
  args=()
  parse_client "$@"
  snap=$(cmd_snapshot)
  if [ "$(printf '%s\n' "$snap" | jq 'length')" -eq 0 ]; then
    tmux_c display-message "agent-watch: no agents"
    return 0
  fi
  while IFS=$'\t' read -r label key cmd; do
    args+=("$label" "$key" "$cmd")
  done < <(printf '%s\n' "$snap" | jq -r \
    --arg need "$C_NEED" --arg work "$C_WORK" --arg rnew "$C_READY_NEW" --arg rold "$C_READY" \
    "$AW_JQ_DEFS"'
    to_entries[] | .key as $i | .value
    | ({needs_you: $need, working: $work, ready: (if .unseen then $rnew else $rold end)}[.state]) as $c
    | ("#[fg=\($c)]●#[default] \(word)  \(.name) · \(.task | .[0:40] | gsub("#"; "##"))") as $label
    | [ (if .target == null then "-" else "" end) + $label,
        (if .target != null and $i < 9 then ($i + 1 | tostring) else "" end),
        (if .target != null then "switch-client -t '"'"'\(.target.pane)'"'"'" else "" end) ]
    | @tsv')
  tmux_c display-menu -T ' agents ' -x C -y C "${args[@]}"
}
```

Add to `main`:

```bash
    menu) cmd_menu "$@" ;;
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bats test/agent-watch.bats && shellcheck bin/agent-watch`
Expected: all pass. The disabled-row test expects `alpha · alpha` because with no pane the task falls back to the name.

- [ ] **Step 5: Try it live**

Run: `tmux bind F12 run-shell -b "$PWD/bin/agent-watch menu -c '#{client_name}'"` then press `Ctrl+a F12`.
Expected: a centred menu listing your running Claude sessions; pressing a number switches to that session and pane. Then `tmux unbind F12`.

- [ ] **Step 6: Commit**

```bash
cd /Users/cam/dotfiles
git add bin/agent-watch test/agent-watch.bats
git commit -m "agent-watch: jump menu

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 8: `toggle` and `ensure`

**Files:**
- Modify: `bin/agent-watch`
- Modify: `test/agent-watch.bats`

**Interfaces:**
- Consumes: `parse_client`, `tmux_c`, `AW_SELF`, `AW_WIDTH`, the `@agent_watch_sidebar` marker from Task 6.
- Produces: `cmd_toggle [-c client]`, `cmd_ensure [-c client]`, `client_ctx` setting `CTX_SESSION` and `CTX_WINDOW`, `find_sidebar`, `open_sidebar`.

- [ ] **Step 1: Write the failing tests**

Append to `test/agent-watch.bats`:

```bash
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bats test/agent-watch.bats`
Expected: fail with "unknown command: toggle" and "unknown command: ensure".

- [ ] **Step 3: Implement toggle and ensure**

In `bin/agent-watch`, add after `cmd_menu`:

```bash
CTX_SESSION=""
CTX_WINDOW=""

# client_ctx   fills CTX_SESSION and CTX_WINDOW for the client's current window
client_ctx() {
  local out width
  out=$(tmux_c display-message -p "#{session_name}${TAB}#{window_id}${TAB}#{window_width}") \
    || die "cannot query tmux client"
  IFS="$TAB" read -r CTX_SESSION CTX_WINDOW width <<<"$out"
  [ -n "${CTX_SESSION:-}" ] && [ -n "${CTX_WINDOW:-}" ] || die "cannot resolve the current window"
  : "$width"
}

# find_sidebar   prints the sidebar pane id in CTX_WINDOW, or nothing
find_sidebar() {
  "$AW_TMUX" list-panes -t "$CTX_WINDOW" -F "#{pane_id}${TAB}#{@agent_watch_sidebar}" 2>/dev/null \
    | awk -F '\t' '$2 == "1" { print $1; exit }'
}

open_sidebar() {
  "$AW_TMUX" split-window -fh -l "$AW_WIDTH" -d -t "$CTX_WINDOW" "$AW_SELF sidebar"
}

# toggle [-c client]
cmd_toggle() {
  local sb
  parse_client "$@"
  client_ctx
  sb=$(find_sidebar)
  if [ -n "$sb" ]; then
    "$AW_TMUX" kill-pane -t "$sb"
    "$AW_TMUX" set-option -t "$CTX_SESSION" @agent_watch off
  else
    open_sidebar
    "$AW_TMUX" set-option -t "$CTX_SESSION" @agent_watch on
  fi
}

# ensure [-c client]   open the sidebar unless present or the session opted out
cmd_ensure() {
  local opt
  parse_client "$@"
  client_ctx
  opt=$("$AW_TMUX" show-options -t "$CTX_SESSION" -qv @agent_watch 2>/dev/null || true)
  [ "$opt" = "off" ] && return 0
  [ -n "$(find_sidebar)" ] && return 0
  open_sidebar
}
```

Add to `main`:

```bash
    toggle) cmd_toggle "$@" ;;
    ensure) cmd_ensure "$@" ;;
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bats test/agent-watch.bats && shellcheck bin/agent-watch`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
cd /Users/cam/dotfiles
git add bin/agent-watch test/agent-watch.bats
git commit -m "agent-watch: toggle and ensure for the sidebar pane

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 9: tmux wiring, symlink, docs and live verification

**Files:**
- Modify: `tmux/.config/tmux/tmux.conf`
- Create: `docs/agent-watch.md`
- Create (outside repo): symlink `~/.local/bin/agent-watch`

**Interfaces:**
- Consumes: every subcommand from Tasks 2 to 8.

- [ ] **Step 1: Symlink the script like tmux-mem**

Run: `ln -sf /Users/cam/dotfiles/bin/agent-watch ~/.local/bin/agent-watch && ~/.local/bin/agent-watch --help | head -3`
Expected: usage text.

- [ ] **Step 2: Edit tmux.conf**

In `tmux/.config/tmux/tmux.conf`, change the two status-right lines under `# ── Status Bar` from:

```tmux
set -g status-right-length 50
set -g status-right "#[fg=#bd5eff]#{b:pane_current_path} #[fg=#3c4048]| #[fg=#ff6e5e]%H:%M "
```

to:

```tmux
set -g status-right-length 80
set -g status-right "#(~/.local/bin/agent-watch brief) #[fg=#bd5eff]#{b:pane_current_path} #[fg=#3c4048]| #[fg=#ff6e5e]%H:%M "
```

Then add this block directly above `# ── TPM Plugins`:

```tmux
# ── Agent watch (AI agent sidebar, see docs/agent-watch.md) ─────────────
bind a run-shell -b "~/.local/bin/agent-watch menu -c '#{client_name}'"
bind b run-shell -b "~/.local/bin/agent-watch toggle -c '#{client_name}'"
set-hook -g client-attached { run-shell -b "~/.local/bin/agent-watch ensure -c '#{hook_client}'" }
set-hook -g client-session-changed { run-shell -b "~/.local/bin/agent-watch ensure -c '#{hook_client}'" }
```

- [ ] **Step 3: Reload and verify the bindings and hooks registered**

Run: `tmux source-file ~/.config/tmux/tmux.conf && tmux list-keys -T prefix | grep -E ' (a|b) ' && tmux show-hooks -g | grep -E 'client-(attached|session-changed)'`
Expected: two bind lines and two hook lines, each mentioning agent-watch.

- [ ] **Step 4: Live checks (do each, note the result)**

1. Press `Ctrl+a b` in a dev session. Expected: a 34-column sidebar on the right with a card per Claude session; focus stays where it was.
2. Press `Ctrl+a b` again. Expected: the sidebar closes. Run `tmux show-options -v @agent_watch`; expected `off`.
3. Press `Ctrl+a b` once more so it is open, then switch to another session with `Ctrl+a s`. Expected: that session gains a sidebar within a moment (the `client-session-changed` hook).
4. Press `Ctrl+a a`. Expected: a centred menu; a number key jumps to that agent's pane.
5. In a session whose Claude is idle, look at the sidebar: its card should be green (unseen) if you haven't visited that pane since it finished, and dim once you have.
6. Watch the top-right of the status bar in any session. Expected: coloured glyphs with counts, e.g. `● 1 ● 2`.
7. Ask a Claude session a question that makes it call AskUserQuestion (or wait for a permission prompt). Expected: its card moves to the top, red, with "input needed" or "permission prompt".

If check 3 opens a sidebar in a session you don't want one in, press `Ctrl+a b` there once; it stays off.

- [ ] **Step 5: Write the docs**

Create `docs/agent-watch.md`:

```markdown
# agent-watch

A tmux sidebar, status-bar segment and jump menu showing every running
Claude Code session as **working**, **needs you** or **ready**.

## Keys

| Keys       | Effect                                      |
|------------|---------------------------------------------|
| `Ctrl+a a` | jump menu: press a number to go to that agent |
| `Ctrl+a b` | show or hide the sidebar in this window      |

The sidebar opens automatically in a session when you attach or switch to
it. Hiding it with `Ctrl+a b` keeps it off for that session.

## What the cards mean

```
1 ● needs you · input needed · 2m   <- number, state, why, time in state
  tsb-drupal-f4                     <- session name (/rename to change)
  Tmux side panel for AI agent      <- the pane title Claude Code sets
  progress
```

- **needs you** (red): a question or permission prompt is open. Longest
  waiting first.
- **ready** (green): finished and you haven't looked at it since. Dim once
  you've visited the pane.
- **working** (cyan): running, including background subagents and scripts.

The status bar shows the same counts: `● needs you  ● ready  ● working`.

## Where the data comes from

Claude Code keeps `~/.claude/sessions/<pid>.json` for each live session
with its `status` (`busy`, `shell`, `waiting`, `idle`), its tmux pane and
its name. `agent-watch snapshot` reads those, adds the pane title from
tmux, tracks which panes you've looked at, and prints sorted JSON. All
views read that.

## Commands

```
agent-watch snapshot          JSON array of live agents, sorted
agent-watch brief             one-line tmux status segment
agent-watch sidebar [--once]  run the sidebar in the current pane
agent-watch render [--width N] [--plain] [--now EPOCH]   render stdin JSON
agent-watch menu [-c client]  jump menu
agent-watch toggle [-c client]
agent-watch ensure [-c client]
```

Environment overrides: `AGENT_WATCH_SESSIONS_DIR`, `AGENT_WATCH_STATE_DIR`,
`AGENT_WATCH_TMUX`, `AGENT_WATCH_WIDTH` (34), `AGENT_WATCH_INTERVAL` (2).

## Adding another agent CLI

Add a `provider_<name>` function in `bin/agent-watch` that prints one JSON
object per agent with `provider id session_id name cwd raw_status
waiting_for since tmux`, and call it from `cmd_snapshot` next to
`provider_claude`. Map that tool's own statuses onto `busy`, `shell`,
`waiting`, `idle` in the provider so `map_state` stays shared.

## Tests

```
brew install bats-core shellcheck
bats test/agent-watch.bats
shellcheck bin/agent-watch
```
```

- [ ] **Step 6: Final lint and full test run**

Run: `cd /Users/cam/dotfiles && shellcheck bin/agent-watch test/fixtures/agent-watch/fake-tmux test/helpers.bash && bats test/agent-watch.bats`
Expected: shellcheck silent; every test passes.

- [ ] **Step 7: Commit**

```bash
cd /Users/cam/dotfiles
git add tmux/.config/tmux/tmux.conf docs/agent-watch.md
git commit -m "agent-watch: tmux keys, hooks, status segment and docs

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```
