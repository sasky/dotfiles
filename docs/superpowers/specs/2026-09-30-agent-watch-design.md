# agent-watch: tmux sidebar for AI agent sessions

Status: experiment. Branch `experiment/agent-watch` in this repo.

## Goal

Cam runs one Claude Code session per project, each in its own tmux session.
Today the only way to learn that an agent has finished or is waiting on input
is to cycle through sessions or catch a macOS notification. agent-watch gives a
glanceable view inside tmux of every running agent: whether it is working,
waiting on Cam, or ready for the next prompt, plus a key to jump straight to it.

Success: never lose track of an idle or waiting agent again, without leaving
the per-project dev session.

## Non-goals for v1

- Agents other than Claude Code. The design leaves a seam for codex, pi and
  opencode, but only the Claude Code provider is built.
- Replying to an agent from the panel, or any detail beyond the pane title.
- Mouse interaction with the sidebar.
- A control-room session. The sidebar lives inside each dev session.

## Architecture

One bash script, `bin/agent-watch`, split into a collector and three views.

```
~/.claude/sessions/*.json ──┐
tmux pane titles ───────────┤
seen-file ──────────────────┼──▶ snapshot (JSON) ──▶ sidebar  (pane, 2 s loop)
                            │                    ├──▶ brief    (status-right, 5 s)
                            │                    └──▶ menu     (prefix + a)
                            └── providers: claude (v1), others later
```

Everything reads `snapshot`. There is no daemon: the sidebar loop, the
status-bar segment and the menu each call the collector on demand.

## Collector: `agent-watch snapshot`

Prints a JSON array, one entry per live agent, already sorted.

```json
{
  "provider": "claude",
  "id": "82993",
  "session_id": "a1b56051-b005-47c9-8fe4-890f6535343a",
  "name": "tsb-drupal-f4",
  "task": "Tmux side panel for AI agent progress",
  "state": "needs_you",
  "detail": "input needed",
  "since": 1790739236,
  "unseen": false,
  "cwd": "/Users/cam/Sites/tsb/tsb_drupal",
  "target": { "session": "tsb_drupal", "window": "@0", "pane": "%2" }
}
```

- `id` is provider-scoped. The Claude provider uses the process id.
- `state` is exactly one of `working`, `needs_you`, `ready`.
- `detail` is secondary text: the registry's `waitingFor` for needs_you
  ("input needed" or "permission prompt"), "background script" when a working
  session's main loop is idle but a shell is still running, otherwise empty.
- `since` is epoch seconds when the agent entered its current state.
- `unseen` is meaningful only for `ready`. See Seen-tracking.
- `target` is null when the pane can no longer be found.

### Providers

A provider is a bash function `provider_<name>` that emits zero or more
entries in the shape above. `snapshot` concatenates all providers, applies the
seen-tracking pass, sorts, and prints. Adding an agent CLI later means adding
one function; no view changes.

### Claude Code provider

Source: `~/.claude/sessions/<pid>.json`, the live-session registry Claude Code
maintains for its own `/list-agents` and `claude agents` features. Path is
overridable with `AGENT_WATCH_SESSIONS_DIR`.

For each file:

1. Skip if the JSON is unreadable or the `pid` is not alive. Claude Code
   cleans stale files itself, but the check is cheap insurance.
2. Read `pid`, `sessionId`, `name`, `cwd`, `status`, `statusUpdatedAt`,
   `waitingFor`, `tmux`.
3. Map status to state:

   | Registry `status` | State      | Detail                              |
   |-------------------|------------|-------------------------------------|
   | `busy`            | working    |                                     |
   | `shell`           | working    | background script                   |
   | `waiting`         | needs_you  | registry `waitingFor`               |
   | `idle`            | ready      |                                     |
   | anything else     | working    | the raw status, so drift is visible |

4. Parse `tmux` (`session:@window.%pane`) into `target`. Ask tmux for that
   pane's title and strip the leading glyph to get `task`. If the pane is
   gone, `target` is null and `task` falls back to `name`.
5. `since` is `statusUpdatedAt` in seconds.

Why this covers "busy until subagents and scripts resolve": Claude Code's own
status derivation reports `busy` while delegated work (background subagents)
is active and `shell` while a background command is still running, and only
`idle` once nothing is pending. Verified by sampling the registry while this
session's turn ended with a background script and, separately, a background
subagent running. See Findings.

### Seen-tracking

Purpose: make a finished run stand out until Cam has looked at it.

- State file `~/.local/state/agent-watch/seen.json`, overridable with
  `AGENT_WATCH_STATE_DIR`. Map of `"<provider>:<id>"` to epoch seconds.
- Every `snapshot` call asks tmux for the active pane of each attached
  client's current window. Any agent whose target pane is one of those gets
  its seen time set to now. Written atomically (temp file then rename), so
  several concurrent sidebars can't corrupt it.
- `unseen` is true when state is `ready` and there is no seen time, or the
  seen time is earlier than `since`.
- Entries for ids no longer present are pruned on write.

Because every view calls `snapshot`, the file stays fresh even in a session
with no sidebar open: the status-bar segment alone keeps it current.

### Sort order

Fixed in the collector so all views agree and card numbers match menu keys:

1. `needs_you`
2. `ready` with `unseen` true
3. `working`
4. `ready` with `unseen` false

Within a group, longest in the current state first (`since` ascending), so the
agent that has waited longest on Cam is at the top.

## Views

### Sidebar: `agent-watch sidebar`

Runs inside a tmux pane. Loop: snapshot, render, redraw, sleep 2 s.

Layout at the default 34 columns:

```
1 needs you · 1 ready · 1 working
1 ● needs you · 2m · permission
  tsb-drupal-f4
  Tmux side panel for AI agent
  progress
2 ● ready · 5m
  migration-tools-22
  UK meta FSI returned
3 ● working · 12m
  vision-super-website-2e
  News section bug tickets
C-a a jump · C-a b hide
```

- Header: counts per non-empty state, needs you then ready then working.
  With all three states present it is 33 characters, so it fits the default
  width; with no agents it reads `AGENTS`.
- Card: line one is the card number, state glyph, state, time in state
  (`45s`, `2m`, `1h12m`), then the detail when present. The age comes before
  the detail so it survives at 34 columns; details are shortened for display
  (`permission`, `input`, `bg script`). Line two is the session name. Lines
  three and four are the task wrapped at width minus indent, truncated with
  an ellipsis after two lines.
- Any line longer than the width ends in an ellipsis rather than being cut.
- Colours, from the cyberdream palette already used in the status bar:
  needs_you `#ff6e5e`, working `#5ef1ff`, ready unseen `#5eff6c`, ready seen
  `#3c4048`. The glyph, state word and card number carry the colour.
- Below 24 columns, cards collapse to one line: number, glyph, name.
- No agents: header plus a single dim line "no agents".
- Redraw moves the cursor home and rewrites each line with clear-to-end-of-
  line, then clears to end of screen, so there is no full-screen flash.
  Cursor hidden while running, restored on exit. SIGWINCH triggers an
  immediate redraw.
- Width enforcement: on start and on resize, if the pane is not 34 columns
  and the window is wider than 80, the sidebar resizes its own pane to 34.
  This is what makes a pane opened by a hook before the window had its real
  size come out right.
- The sidebar marks its pane with the user option `@agent_watch_sidebar`
  so toggle and ensure can find it.
- The sidebar draws on the default background and therefore inherits the
  dimmed inactive-pane style, which is the intended look.

### Status-bar segment: `agent-watch brief`

Prints one tmux format string for `status-right`; tmux runs it every
status-interval (5 s). Output is one glyph and count per non-empty state in
sort order, coloured as above, with ready shown green when any ready agent is
unseen and dim otherwise. Prints nothing when no agents are running so the bar
stays clean in sessions with no Claude. Must finish well under the status
interval; expected cost is tens of milliseconds.

### Jump menu: `agent-watch menu`

Builds a tmux `display-menu`, centred, with one row per agent in snapshot
order. Each row's key is its card number (1 to 9; further agents are listed
without a key). Row text: glyph, state, name, and the task truncated to fit.
Selecting a row switches the client to the agent's session, selects its
window, then its pane. Rows whose target is null are rendered disabled. With
no agents the command shows a one-line "agent-watch: no agents" message
instead of a menu.

Jumping to a ready agent clears its unseen flag on the next tick through the
ordinary seen-tracking; the menu does no bookkeeping of its own.

## tmux integration

### Keys

| Keys        | Command                 | Effect                                  |
|-------------|-------------------------|-----------------------------------------|
| `Ctrl+a a`  | `agent-watch menu`      | jump menu                               |
| `Ctrl+a b`  | `agent-watch toggle`    | show or hide the sidebar in this window |

Both letters are currently unbound in the prefix table. `Ctrl+a Ctrl+a`
continues to send a literal Ctrl+a.

### Toggle and ensure

`toggle` acts on the client's current window:

- Sidebar pane present: kill it and set the session option `@agent_watch`
  to `off`, so nothing reopens it in this session.
- Absent: split a full-height 34-column pane on the right, without taking
  focus, running `agent-watch sidebar`; set `@agent_watch` to `on`.

`ensure` is the idempotent form used by hooks and scripts: do nothing if the
session has `@agent_watch off` or the current window already has a sidebar;
otherwise open one. Takes a few milliseconds.

Both accept `-c <client>` so hooks can pass the client that triggered them,
and fall back to the current client.

### Hooks

One global hook, `client-session-changed`, runs `agent-watch ensure` for
that client in the background. On tmux 3.7 this hook also fires on
`attach` and on the server-start `new-session`, so it covers every way of
landing in a session. A second `client-attached` hook is not used: on
attach both fire within a millisecond, both pass the "already has a
sidebar" check, and two sidebars open (found in review). `ensure` and
`toggle` also take a per-window `mkdir` lock around that check, with a
10-second staleness limit, so a double keypress can't do the same.
Result: every dev session Cam lands in gets a sidebar unless that session
was toggled off.

New windows created later in a session do not get a sidebar automatically;
`Ctrl+a b` adds one. This keeps the hook set small for the experiment.

### tmux.conf changes

- The two key bindings.
- The `client-session-changed` hook.
- `status-right` gains `#(~/.local/bin/agent-watch brief)` ahead of the
  current path segment.

### Interaction with existing setup

- vim-tmux-navigator: `Ctrl+l` from the rightmost work pane lands in the
  sidebar; `Ctrl+h` returns. Accepted for v1. A later refinement can add a
  bounce-back to the `Ctrl+l` binding when the landing pane has
  `@agent_watch_sidebar` set.
- tmux-resurrect and continuum are configured in tmux.conf but TPM is not
  installed on this machine, so they are inert. Nothing to do now. If TPM is
  installed later, `@resurrect-processes '"~agent-watch sidebar"'` restores
  the sidebar pane with its process.
- The existing Claude Code Notification hook (`~/.claude/scripts/notify.sh`)
  is untouched and complementary.

## Files

| Path                                   | Change                                        |
|----------------------------------------|-----------------------------------------------|
| `bin/agent-watch`                      | new; bash; subcommands snapshot, brief, sidebar, menu, toggle, ensure |
| `~/.local/bin/agent-watch`             | symlink to the above, like `tmux-mem`         |
| `tmux/.config/tmux/tmux.conf`          | binds, hooks, status-right segment            |
| `docs/agent-watch.md`                  | new; what it shows, keys, adding a provider   |
| `test/agent-watch.bats`                | new; collector and view tests                 |
| `test/fixtures/agent-watch/`           | new; registry files, seen files, fake tmux    |
| `Brewfile`                             | add `bats-core`, `shellcheck`                 |

Dependencies at runtime: bash 3.2+ (macOS default is fine), `jq`, `tmux`.

## Error handling

- No registry directory, or no live agents: sidebar shows "no agents",
  brief prints nothing, menu shows a one-line message. Exit 0.
- A registry file that is unreadable JSON, or whose pid is dead: skipped.
- A registry entry missing `tmux`, or whose pane is gone: shown with a null
  target, not selectable in the menu, task falls back to name.
- An unknown registry status: shown as working with the raw status as
  detail, so format drift is visible rather than hidden.
- `jq` missing: one clear error to stderr, exit 1. Views never loop on it.
- tmux server not running when `brief` is called: cannot happen, tmux is the
  caller. `snapshot` outside tmux still works for tests and debugging; seen-
  tracking is skipped when there are no clients.
- The sidebar restores the cursor on exit via an EXIT trap.

## Testing

Install `bats-core` and `shellcheck` via the Brewfile.

Test seams, all environment variables:

- `AGENT_WATCH_SESSIONS_DIR`: registry directory.
- `AGENT_WATCH_STATE_DIR`: seen-file directory.
- `AGENT_WATCH_TMUX`: path to the tmux binary; tests point it at a fake
  script that answers `list-panes`, `display-message`, `list-clients`,
  `display-menu`, `split-window`, `kill-pane` and `set-option` from fixture
  files and records its arguments.
- `AGENT_WATCH_ALIVE_PIDS`: when set, only these pids count as alive.

Cases:

1. Status mapping: busy, shell, waiting with each `waitingFor`, idle, and an
   unknown value.
2. Skips: dead pid, malformed JSON, missing `tmux` field, pane not found.
3. Task text: glyph stripped from the pane title; fallback to name.
4. Sort order across all four groups and by `since` within a group.
5. Seen-tracking: unseen when no seen time; unseen when seen is before
   since; seen when after; snapshot writes the seen time when the fake tmux
   reports the client on the agent's pane; pruning of departed ids.
6. `brief`: counts, colours, ready green versus dim, empty output.
7. `menu`: argument list passed to display-menu, disabled row for null
   target, no-agents message.
8. `toggle` and `ensure`: split when absent, kill when present, respect for
   `@agent_watch off`, idempotence.
9. shellcheck clean.

The sidebar rendering and the live keybindings are checked by hand in Cam's
running sessions.

## Performance

Snapshot: four to six small JSON files plus three tmux queries, about 20 ms.
Sidebar: one process per dev session, one tick every 2 s. Brief: one call
every 5 s per tmux status refresh. All negligible.

## Future

- Providers for codex, pi and opencode, each with whatever state source that
  CLI exposes.
- Mouse click on a card to jump, which needs a real TUI instead of a bash
  loop.
- Navigator bounce-back on `Ctrl+l`.
- Sidebar in every window of a session, not just the one you land in.

## Findings (recorded so the plan doesn't re-derive them)

- Registry: `~/.claude/sessions/<pid>.json`, one per live session, fields
  include `pid`, `sessionId`, `cwd`, `name`, `status`, `statusUpdatedAt`,
  `waitingFor`, `tmux` (`session:@window.%pane`), `messagingSocketPath`.
  Not documented as a stable format; treat as internal.
- Status enum in the binary: `["busy","shell","idle","waiting"]`.
  Derivation: `waiting` whenever a dialog is open for the user, with
  `waitingFor` "input needed" for questions and elicitations or "permission
  prompt" otherwise; `busy` when the main loop is loading or delegated work
  is active; otherwise `idle`. `shell` is written when the turn has ended but
  a background command is still running.
- Probe results (this session, 2026-09-30): turn ended with a background
  script running gave `shell`; turn ended with a background subagent active
  gave `busy`; subagent parked on its own background script gave `shell`;
  never `idle` while anything was pending.
- `claude agents --json` is the documented scriptable list. It does not
  start the supervisor daemon, costs about 120 ms, and omits the tmux
  target. Kept as the fallback if the registry format changes.
- Claude Code sets each pane's title to `✳ <task summary>`; tmux exposes it
  as `pane_title`.
- Claude Code hooks (`Stop`, `Notification`, `SubagentStart`,
  `SubagentStop`, `SessionEnd`) exist and support async, but are not needed
  for v1 because the registry already carries every state the panel shows.
- tmux 3.7c here supports `display-menu`, `display-popup`, user options in
  formats, and the `client-attached` and `client-session-changed` hooks.
- Free unshifted prefix letters at design time: a, b, e, g, u, v, y.
