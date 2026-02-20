# How Format-on-Save Works in LazyVim

## The Stack

1. **conform.nvim** - The formatting engine
2. **LazyVim's Prettier Extra** - Pre-configured setup
3. **Mason** - Auto-installs formatters

## Under the Hood

### 1. conform.nvim Setup

When LazyVim loads the prettier extra, it configures conform.nvim like this:

```lua
{
  "stevearc/conform.nvim",
  opts = {
    -- Formatters by file type
    formatters_by_ft = {
      javascript = { "prettier" },
      typescript = { "prettier" },
      javascriptreact = { "prettier" },
      typescriptreact = { "prettier" },
      css = { "prettier" },
      html = { "prettier" },
      json = { "prettier" },
      yaml = { "prettier" },
      markdown = { "prettier" },
      php = { "prettier" },  -- PHP uses prettier
      -- ... more file types
    },
    -- Format on save configuration
    format_on_save = {
      timeout_ms = 3000,
      lsp_fallback = true,  -- Use LSP formatting if conform formatter not available
    },
  },
}
```

### 2. Format-on-Save Trigger

LazyVim creates an autocmd that runs on `BufWritePre` (before buffer write):

```lua
vim.api.nvim_create_autocmd("BufWritePre", {
  pattern = "*",
  callback = function(args)
    require("conform").format({
      bufnr = args.buf,
      timeout_ms = 3000,
      lsp_fallback = true,
    })
  end,
})
```

### 3. The Format Flow

When you save a PHP file:
1. `BufWritePre` event fires
2. conform.nvim checks `formatters_by_ft.php`
3. Finds `prettier` in the list
4. Runs: `prettier --write your-file.php`
5. If prettier fails/missing → falls back to LSP formatting (intelephense)
6. Buffer gets the formatted content
7. File saves with formatted code

## How to Customize

### Option 1: Override Prettier Configuration

Create `lua/plugins/conform.lua`:

```lua
return {
  "stevearc/conform.nvim",
  opts = {
    formatters_by_ft = {
      -- Change PHP formatter
      php = { "php_cs_fixer" },  -- Use PHP CS Fixer instead
      -- or
      php = { "pint" },  -- Use Laravel Pint
      -- or disable
      php = {},  -- No formatter for PHP
    },
    -- Customize format-on-save
    format_on_save = function(bufnr)
      -- Disable for PHP files
      if vim.bo[bufnr].filetype == "php" then
        return nil
      end
      return { timeout_ms = 3000, lsp_fallback = true }
    end,
  },
}
```

### Option 2: Configure Prettier Options

Create `.prettierrc` in your project root:

```json
{
  "printWidth": 120,
  "tabWidth": 4,
  "phpVersion": "8.1",
  "braceStyle": "psr-2"
}
```

### Option 3: Add Multiple Formatters (Run in Sequence)

```lua
formatters_by_ft = {
  php = { "php_cs_fixer", "prettier" },  -- Runs php_cs_fixer, then prettier
}
```

### Option 4: Disable Auto-Format, Use Manual

```lua
return {
  "stevearc/conform.nvim",
  opts = {
    format_on_save = nil,  -- Disable auto-format
  },
  keys = {
    {
      "<leader>cf",
      function()
        require("conform").format({ async = true, lsp_fallback = true })
      end,
      mode = "",
      desc = "Format buffer",
    },
  },
}
```

## Installing Alternative PHP Formatters

### PHP CS Fixer
```bash
# Install globally
composer global require friendsofphp/php-cs-fixer

# Or add to Mason
:MasonInstall php-cs-fixer
```

### Laravel Pint
```bash
composer global require laravel/pint
# or in project: composer require laravel/pint --dev
```

### Phpcbf (PHP_CodeSniffer)
```bash
:MasonInstall phpcbf
```

## Debugging Format-on-Save

```lua
-- Add to lua/config/autocmds.lua
vim.api.nvim_create_autocmd("BufWritePre", {
  pattern = "*.php",
  callback = function()
    print("Formatting PHP file...")
    print("Formatters: " .. vim.inspect(require("conform").list_formatters(0)))
  end,
})
```

## Checking What's Actually Running

```vim
" In Neovim, run these commands:
:lua print(vim.inspect(require("conform").list_formatters(0)))
:ConformInfo
```
