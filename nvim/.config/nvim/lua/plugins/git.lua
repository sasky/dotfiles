return {
  {
    "NeogitOrg/neogit",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "sindrets/diffview.nvim",
    },
    keys = {
      { "<leader>gn", function() require("neogit").open() end, desc = "Neogit Status" },
    },
    opts = {
      integrations = {
        diffview = true,
      },
    },
  },
  {
    "sindrets/diffview.nvim",
    cmd = { "DiffviewOpen", "DiffviewFileHistory" },
    keys = {
      { "<leader>gd", "<cmd>DiffviewOpen<cr>", desc = "Diffview Open" },
      { "<leader>gh", "<cmd>DiffviewFileHistory %<cr>", desc = "Diffview File History" },
      {
        "<leader>gD",
        function()
          local gitbase = require("util.git_base")
          local root = gitbase.buffer_root()
          if not root then
            vim.notify("Not inside a git repository", vim.log.levels.WARN)
            return
          end
          vim.ui.input({ prompt = "Diffview against base: ", default = gitbase.default_base(root) }, function(base)
            if base and base ~= "" then
              vim.cmd("DiffviewOpen -C" .. vim.fn.fnameescape(root) .. " " .. base .. "...HEAD --imply-local")
            end
          end)
        end,
        desc = "Diffview vs base (PR-style)",
      },
    },
  },
}
