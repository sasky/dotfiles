return {
  -- Use intelephense instead of phpactor for PHP LSP
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        phpactor = { enabled = false },
        intelephense = { enabled = true },
      },
    },
  },

  -- Override lang.php Mason list: only php-cs-fixer, no phpcs
  {
    "mason-org/mason.nvim",
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}
      -- Remove phpcs if the lang.php extra added it
      for i = #opts.ensure_installed, 1, -1 do
        if opts.ensure_installed[i] == "phpcs" then
          table.remove(opts.ensure_installed, i)
        end
      end
    end,
  },

  -- Use PHPStan for linting instead of phpcs
  {
    "mfussenegger/nvim-lint",
    optional = true,
    opts = {
      linters_by_ft = {
        php = { "phpstan" },
      },
    },
  },
}
