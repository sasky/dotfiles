return {
  -- Install cspell-lsp binary via Mason
  {
    "mason-org/mason.nvim",
    opts = {
      ensure_installed = { "cspell" },
    },
  },
  -- Configure cspell-lsp via lspconfig
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        cspell = {},
      },
    },
  },
}
