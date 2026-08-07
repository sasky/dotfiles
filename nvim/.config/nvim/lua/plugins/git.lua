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
          local default = vim.fn.systemlist("git symbolic-ref --short refs/remotes/origin/HEAD")[1]
          default = (vim.v.shell_error == 0 and default) or "main"
          vim.ui.input({ prompt = "Diffview against base: ", default = default }, function(base)
            if base and base ~= "" then
              vim.cmd("DiffviewOpen " .. base .. "...HEAD --imply-local")
            end
          end)
        end,
        desc = "Diffview vs base (PR-style)",
      },
    },
  },
}
