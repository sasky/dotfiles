return {
  -- VSCode diff engine (review.nvim renders through it); downloads a prebuilt lib on first use
  {
    "esmuellert/codediff.nvim",
    cmd = "CodeDiff",
    -- pinned below 2.50: newer codediff returns typed Path objects from
    -- get_paths, which review.nvim can't consume yet — unpin once
    -- georgeguimaraes/review.nvim#37 is merged and released
    version = "2.49.2",
  },

  -- Branch review with typed inline comments, exported to an AI session
  {
    "georgeguimaraes/review.nvim",
    -- "*" = latest release; the README's "v*" is not a valid lazy.nvim semver
    -- range and crashes the update checker (lazy/manage/git.lua:58)
    version = "*",
    dependencies = {
      "esmuellert/codediff.nvim",
      "MunifTanjim/nui.nvim",
    },
    cmd = { "Review" },
    keys = {
      {
        "<leader>gR",
        function()
          local gitbase = require("util.git_base")
          -- review.nvim/codediff run git against nvim's cwd, so that's what we review
          local root = gitbase.root_of(vim.fn.getcwd())
          if not root then
            vim.notify("nvim's cwd is not a git repo — :cd into the repo first (Review uses the cwd)", vim.log.levels.WARN)
            return
          end
          vim.ui.input({ prompt = "Review HEAD against base: ", default = gitbase.default_base(root) }, function(base)
            if not base or base == "" then
              return
            end
            -- diff from the merge-base, not the base tip: PR semantics (only this branch's changes)
            local mb = vim.fn.systemlist({ "git", "-C", root, "merge-base", base, "HEAD" })[1]
            if vim.v.shell_error ~= 0 or not mb or mb == "" then
              vim.notify("git merge-base " .. base .. " HEAD failed in " .. root, vim.log.levels.ERROR)
              return
            end
            vim.cmd("Review commits " .. mb .. " HEAD")
          end)
        end,
        desc = "Review branch vs base (PR-style)",
      },
    },
    opts = {},
    config = function(_, opts)
      require("review").setup(opts)
      -- codediff's explorer auto-refresh re-selects the current file, which makes
      -- review.nvim re-run its session setup and steal focus to the diff pane on
      -- every tick (review.nvim#31). Allow the initial focus only, once per tab.
      local hooks = require("review.hooks")
      local focus, focused = hooks._focus_modified_pane, {}
      hooks._focus_modified_pane = function(lifecycle, tabpage)
        if focused[tabpage] then
          return
        end
        focused[tabpage] = true
        focus(lifecycle, tabpage)
      end
    end,
  },

  -- AI CLI terminal; review.nvim sends comments into it via S / :Review sidekick
  {
    "folke/sidekick.nvim",
    opts = {
      nes = { enabled = false }, -- no Copilot subscription; CLI integration only
      cli = {
        mux = { backend = "tmux", enabled = true }, -- persistent Claude sessions in tmux
      },
    },
    keys = {
      {
        "<leader>ac",
        function()
          require("sidekick.cli").toggle({ name = "claude", focus = true })
        end,
        desc = "Sidekick Toggle Claude",
      },
      {
        "<leader>aa",
        function()
          require("sidekick.cli").toggle()
        end,
        desc = "Sidekick Toggle CLI",
      },
      {
        "<leader>as",
        mode = "x",
        function()
          -- ui.input is async (snacks), which drops visual mode before send;
          -- exit visual to set the '< '> marks now, restore with gv on send
          vim.cmd([[execute "normal! \<Esc>"]])
          vim.ui.input({ prompt = "Comment for Claude (empty sends bare selection): " }, function(comment)
            if comment == nil then
              return
            end
            vim.cmd("normal! gv")
            -- {position} renders a Claude Code @file:Lx-Ly mention for the selection
            local msg = comment ~= "" and (comment .. "\n{position}\n{selection}") or "{position}\n{selection}"
            require("sidekick.cli").send({ msg = msg })
          end)
        end,
        desc = "Send selection + comment to Claude",
      },
      {
        "<leader>ap",
        mode = { "n", "x" },
        function()
          require("sidekick.cli").prompt()
        end,
        desc = "Sidekick prompt picker (explain/fix/tests/…)",
      },
    },
  },
}
