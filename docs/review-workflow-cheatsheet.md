# Branch Review → Claude Workflow Cheatsheet

PR-style code review inside nvim, with comments sent straight into a Claude
Code session. Stack: diffview.nvim + review.nvim (on codediff.nvim) +
sidekick.nvim. Config lives in `nvim/.config/nvim/lua/plugins/review.lua`
and `git.lua`.

## The loop

```
┌───────────────────────────┐  ┌──────────────────────┐
│ tmux pane 1: nvim         │  │ tmux pane 2: claude  │
│                           │  │ (cd'd into the repo) │
│ <leader>gR → pick base    │  │                      │
│ browse diff, i to comment │  │                      │
│ S ──────── comments ─────────▶ lands in the prompt  │
│                           │  │ claude applies fixes │
│ <leader>gR again to       │◀─│                      │
│ re-review the new state   │  │                      │
└───────────────────────────┘  └──────────────────────┘
```

1. Start claude in a tmux pane, **cd'd into the repo** (sidekick discovers
   it by scanning tmux panes for a running claude, cwd disambiguates).
2. `<leader>gR`, enter the base branch (defaults to `origin/HEAD`).
   You get the merge-base diff — only your branch's changes, like a GitHub PR.
3. Walk the diff, leave typed comments.
4. `S` sends all comments into the claude pane. Hit Enter over there.
5. When claude's done, `<leader>gR` again to review the updated branch.

## Launching (normal mode, anywhere)

| Keys | Action |
|---|---|
| `<leader>gR` | **Review branch vs base** — prompts for base, PR-style, with comments |
| `<leader>gD` | Diffview vs base — same prompt, explore-only (no comments), local buffers on the right |
| `<leader>gd` | Diffview of the working tree |
| `<leader>gh` | Diffview file history of current file |
| `<leader>gn` | Neogit status |
| `<leader>ge` | Neo-tree git explorer (working-tree changes sidebar) |
| `<leader>ac` | Toggle a sidekick-managed Claude terminal |
| `<leader>aa` | Sidekick CLI picker (all tools/sessions) |

## Ad-hoc sends — no review session needed

| Keys | Mode | Action |
|---|---|---|
| `<leader>as` | visual | **Send selection + comment to Claude** — prompts for a comment, sends it with an `@file:Lx-Ly` mention and the code |
| `<leader>ap` | normal/visual | Sidekick prompt picker — explain / fix / optimize / tests / diagnostics on `{this}` |

The message Claude receives from `<leader>as`:

```
<your comment>
@crates/hunk-core/src/lib.rs :L3:C1-L5:C16

<the selected code>
```

## Inside a review session (review.nvim)

| Keys | Action |
|---|---|
| `i` | Add comment (prompts for type) |
| `\cn` / `\cs` / `\ci` / `\cp` | Add Note / Suggestion / Issue / Praise directly |
| `e` / `d` | Edit / delete comment under cursor |
| `]n` / `[n` | Next / previous comment |
| `f` | Toggle file panel |
| `S` | **Send comments to Claude via sidekick** |
| `C` | Export comments as markdown to clipboard (paste anywhere) |
| `q` | Close review (auto-exports) |

Comments persist per-branch in `~/.local/share/nvim/review/` (7-day
expiry) — you can quit and resume a review later.

### :Review commands

```vim
:Review                       " review the working tree
:Review commits               " commit picker
:Review commits main feature  " any two revs (branches work)
:Review export                " comments → clipboard
:Review sidekick              " comments → claude (same as S)
:Review close
```

`<leader>gR` wraps `:Review commits <merge-base> HEAD` so you review only
your branch's changes even when the base has moved on.

## Diffview essentials (explore mode)

| Keys | Action |
|---|---|
| `<Tab>` / `<S-Tab>` | Next / previous file |
| `g?` | Help — full keymap list |
| `:DiffviewClose` | Close the diffview tab |

`<leader>gD` opens with `--imply-local`: the right side is your real
buffers, so LSP and edits work mid-review.

## Claude / sidekick / tmux

- **Existing claude pane**: sidekick finds any running claude in any tmux
  pane. `S` pastes comments straight into it. Multiple claudes → picker.
- **Sidekick-created sessions** (`<leader>ac`) run as tmux sessions —
  they survive nvim restarts; reattach from anywhere with
  `tmux attach -t <session>` or `<leader>ac` again.
- An externally-started claude pane can't be embedded into nvim — it stays
  where it is; sidekick only sends to it. That's the normal setup.
- `claude --continue` in the repo dir resumes the most recent conversation
  if you closed the pane.

### tmux reminders (prefix is `Ctrl+a`)

| Keys | Action |
|---|---|
| `Ctrl+a |` / `Ctrl+a -` | Split vertical / horizontal |
| `Ctrl+h/j/k/l` | Move between vim splits AND tmux panes (no prefix) |
| `Ctrl+a z` | Zoom pane (great for fullscreening the review) |
| `Ctrl+a [` | Copy mode (vi keys, `y` → clipboard) |

## Maintenance

- **codediff.nvim is pinned to v2.49.2** — codediff ≥ 2.50 changed
  `get_paths()` to return Path objects, which review.nvim can't consume
  yet. Unpin in `review.lua` once
  [review.nvim#37](https://github.com/georgeguimaraes/review.nvim/pull/37)
  is merged and released.
- review.nvim is pinned to releases (`version = "*"`). Don't use the
  README's `v*` — lazy.nvim's update checker crashes on it.
- Parsers/plugins acting up after an nvim upgrade? Stale treesitter state
  lives in `~/.local/share/nvim/site/parser*` — orphaned `.revision` files
  make installs no-op. Delete revisions without a matching `.so`, then
  `:TSUpdate`.
