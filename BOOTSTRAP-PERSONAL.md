# Personal MacBook Bootstrap — 2017 Intel 15", sasky-only

Written 2026-09-03. For the personal machine: **one GitHub account (sasky), no Google
Drive, no client work, no secrets DMG** — everything comes from GitHub plus fresh
logins, so this file is self-sufficient. Same terminal/tmux/nvim experience as the
main machine, via the same dotfiles repo but the lean `Brewfile.personal`.

Intel differences that matter: Homebrew lives in `/usr/local` (not `/opt/homebrew`),
and a 2017 15" tops out at **macOS Ventura (13)** officially — which is past Apple's
and Homebrew's support window, so occasional formulae build from source (slow) and
some casks may demand a newer macOS. If that bites, OpenCore Legacy Patcher can put a
newer macOS on this hardware — your call, not required for anything below.

---

### 1. Xcode Command Line Tools

**How:**
```sh
xcode-select --install
```

**Why:** Homebrew requires it, `git` comes from it, and nvim-treesitter needs the C
compiler. On old-macOS Homebrew you'll build from source more often, so the compiler
earns its keep here.

---

### 2. Homebrew

**How:**
```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```
Follow the installer's "Next steps" — on Intel that's adding
`eval "$(/usr/local/bin/brew shellenv)"` to `~/.zprofile`.

**Why:** Intel brew installs to `/usr/local` (already on the default PATH, unlike
Apple Silicon), but the shellenv line still sets HOMEBREW_* vars and manpaths — and
keeping it in `~/.zprofile` matches the other machine, where the dotfiles deliberately
don't manage it. Expect a warning that your macOS is unsupported; installs still work,
just sometimes slower.

---

### 3. gh + stow

**How:**
```sh
brew install gh stow
```

**Why:** `gh` handles the GitHub login and uploading your new key; `stow` links the
dotfiles. Needed before the full bundle only so steps 4–6 can run while the big
install would still be churning.

---

### 4. GitHub auth — sasky only

**How:**
```sh
gh auth login    # → GitHub.com → SSH → skip key upload → browser login as sasky
gh auth refresh -h github.com -s admin:public_key   # scope needed to add a key in step 5
```

**Why:** This machine is single-account, so no switching, no cdogcatch. The default
login token can't manage SSH keys — the `refresh` adds the `admin:public_key` scope so
step 5 can register the new key from the terminal.

---

### 5. Fresh SSH key (don't reuse the old one)

**How:**
```sh
mkdir -p ~/.ssh && chmod 700 ~/.ssh
ssh-keygen -t ed25519 -C "cam@sasky.nz" -f ~/.ssh/github-sasky
gh ssh-key add ~/.ssh/github-sasky.pub --title "mbp-2017-intel"
```

Then create `~/.ssh/config`:

```sshconfig
Host github.com-sasky
   HostName github.com
   User git
   IdentityFile ~/.ssh/github-sasky
   IdentitiesOnly yes

Host github.com
   HostName github.com
   User git
   AddKeysToAgent yes
   UseKeychain yes
   IdentitiesOnly yes
   IdentityFile ~/.ssh/github-sasky
```

Test: `ssh -T git@github.com-sasky` and `ssh -T git@github.com` → both "Hi sasky!".

**Why:** A per-machine key means nothing secret has to travel here, and losing this
laptop revokes one key, not your identity. On this machine plain `github.com` URLs are
all you need — one account, one key. The `github.com-sasky` Host block is a
compatibility nicety only: an alias lives in each clone's `.git/config`, not on
GitHub, so it matters only when you paste an alias-form URL
(`git@github.com-sasky:sasky/...`) from the main machine's remotes or docs — with the
block present, those paste without editing. Fresh clones here can just use the plain
URLs GitHub's UI gives you.

---

### 6. Clone dotfiles

**How:**
```sh
git clone git@github.com:sasky/dotfiles.git ~/dotfiles
```

**Why:** Same repo as the main machine — one source of truth for the terminal
experience. Machine differences live entirely in which Brewfile you run (step 7) and
which stow packages you skip. (Plain `github.com` URL — the alias form would work too,
per step 5, but there's no reason to use it here.)

---

### 7. brew bundle — the lean personal set

**How:**
```sh
brew bundle --file=~/dotfiles/Brewfile.personal
```

**Why:** `Brewfile.personal` is the same shell/git/nvim core as the main machine
(zsh, tmux, neovim, fzf, eza, bat, ripgrep, lazygit, mise, rtk, syncthing + ghostty,
claude-code, raycast casks) minus everything work-shaped: no gcloud, no codex, no
dotnet, no docker by default. Hobby extras (dasm, rust helpers, orbstack/colima) are
commented at the bottom — uncomment and re-run when a project wants them. On 2017
hardware, less installed = faster and cooler.

---

### 8. Stow the dotfiles

**How:**
```sh
cd ~/dotfiles && stow -t ~ zsh tmux nvim lazygit git ghostty
```
Open a new terminal, run `nvim` once to let plugins install, then `:MasonInstall typos-lsp`.

**Why:** Identical terminal on both machines. The `git` package's default identity is
sasky (`cam@sasky.nz`) with a cdogcatch override only under `~/Sites/` — this machine
has no `~/Sites`, so every commit is sasky with zero setup. `typos-lsp` is a Mason
package (not in dotfiles), so it's a one-time manual install; nvim's spell-checking
stays silently off without it.

---

### 9. Personal bin scripts + machine-local file

**How:**
```sh
mkdir -p ~/.local/bin && ln -sf ~/dotfiles/bin/* ~/.local/bin/
```
`~/.zshrc.local` is optional — `.zshrc` sources it only if present. Create it the
first time this machine needs a private env var; never commit it.

**Why:** `tmux-mem` and friends live in `~/dotfiles/bin` and are linked, not stowed.
The `.zshrc.local` convention keeps machine secrets out of the public repo.

---

### 10. Node via mise

**How:**
```sh
mise use -g node@24
mise settings add idiomatic_version_file_enable_tools node
```

**Why:** mise is the only version manager (no fnm/nvm/nodenv/pyenv, same policy as
the main machine); `.zshrc` already activates it and gives auto-switch-on-cd. The
settings line honours `.nvmrc` files in older personal repos. No global npm packages —
per-project only.

---

### 11. Claude Code + rtk

**How:**
```sh
claude          # first run → log in
rtk init -g     # answer Y when it offers to patch ~/.claude/settings.json
```

**Why:** Unlike the main machine, there's no restored `~/.claude` here — fresh login,
fresh settings. `rtk init -g` recreates the token-saving wiring from scratch (RTK.md +
the PreToolUse Bash hook); the rtk binary itself came from the Brewfile. Global
skills/memory from the main machine don't carry over — copy pieces of `~/.claude`
across later if you miss them.

---

### 12. Syncthing (Second brain etc.)

**How:**
```sh
brew services start syncthing
```
Open http://localhost:8384, copy this machine's device ID, add it as a new device
from the homelab (or the other MacBook) and share the folders you want here.

**Why:** This is how personal data reaches the machine without Google Drive. New
device = new ID; never copy another machine's syncthing config.

---

### 13. Clone personal repos

**How:**
```sh
mkdir -p ~/Sasky
git clone git@github.com:sasky/<name>.git ~/Sasky/<name>
```

**Why:** Keep the `~/Sasky/` layout — the stowed gitconfig and your muscle memory both
assume it. Plain URLs are fine on this machine (alias-form URLs pasted from the main
machine also work, per step 5). Everything worth having is on the sasky account after the 2026-09 backup
run (homelab, Second brain, courage, AlmaAdventure, Atari, code-crafters, elm-tasker,
sasky.nz.php, …). Clone on demand rather than all at once.

---

### 14. Verify

**How:**
```sh
git -C ~/Sasky/<any-repo> config user.email   # → cam@sasky.nz
gh auth status                                 # sasky, active
node --version && mise doctor
nvim '+checkhealth'
tmux
```
In Claude Code, any shell command should come back rtk-compact (`rtk init --show` to
double-check the hook).

**Why:** Each line proves one seam: identity (stowed git package), auth (step 4), mise
(step 10), the nvim stack (7–8), and the rtk wiring (11). If something's off, fix it
here — this is the last step where the cause is obvious.
