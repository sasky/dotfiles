return {
  -- Install typos-lsp binary via Mason
  {
    "mason-org/mason.nvim",
    opts = {
      ensure_installed = { "typos-lsp" },
    },
  },
  -- Configure typos-lsp via lspconfig
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        typos_lsp = {
          init_options = {
            diagnosticSeverity = "Warning",
          },
        },
      },
    },
  },
}
