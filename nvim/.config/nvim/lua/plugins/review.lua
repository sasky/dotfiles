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
          local default = vim.fn.systemlist("git symbolic-ref --short refs/remotes/origin/HEAD")[1]
          default = (vim.v.shell_error == 0 and default) or "main"
          vim.ui.input({ prompt = "Review HEAD against base: ", default = default }, function(base)
            if not base or base == "" then
              return
            end
            -- diff from the merge-base, not the base tip: PR semantics (only this branch's changes)
            local mb = vim.fn.systemlist("git merge-base " .. vim.fn.shellescape(base) .. " HEAD")[1]
            if vim.v.shell_error ~= 0 or not mb or mb == "" then
              vim.notify("git merge-base " .. base .. " HEAD failed", vim.log.levels.ERROR)
              return
            end
            vim.cmd("Review commits " .. mb .. " HEAD")
          end)
        end,
        desc = "Review branch vs base (PR-style)",
      },
    },
    opts = {},
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
