# agent-watch

A tmux sidebar, status-bar segment and jump menu showing every running
Claude Code session as **working**, **needs you** or **ready**.

## Keys

| Keys       | Effect                                        |
|------------|-----------------------------------------------|
| `Ctrl+a a` | jump menu: press a number to go to that agent |
| `Ctrl+a b` | show or hide the sidebar in this window       |

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
