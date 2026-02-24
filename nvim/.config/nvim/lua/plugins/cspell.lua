return {
  -- Install cspell-lsp binary via Mason
  {
    "mason-org/mason.nvim",
    opts = {
      ensure_installed = { "cspell-lsp" },
    },
  },
  -- Configure cspell-lsp via lspconfig
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        cspell_ls = {},
      },
    },
  },
}
