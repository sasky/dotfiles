-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here
-- todo, remap space space to open recent,
--
--

vim.keymap.set("i", "jk", "<esc>:w<cr>l", { desc = "Exit insert mode and save" })
vim.keymap.set("n", "<leader>w", ":bd<cr>l", { desc = "Close the current buffer" })

-- local builtin = require("telescope.builtin")
-- vim.keymap.set("n", "<leader>ff", builtin.oldfiles, { desc = "Telescope old files" })

function _G.set_terminal_keymaps()
  local opts = { buffer = 0 }
  vim.keymap.set("t", "<esc>", [[<C-\><C-n>]], opts)
  vim.keymap.set("t", "jk", [[<C-\><C-n>]], opts)
  -- C-h/j/k/l handled by vim-tmux-navigator
  vim.keymap.set("t", "<C-w>", [[<C-\><C-n><C-w>]], opts)
end

-- if you only want these mappings for toggle term use term://*toggleterm#* instead

vim.cmd("autocmd! TermOpen term://* lua set_terminal_keymaps()")

vim.keymap.del("n", "<leader>fT")
vim.keymap.del("n", "<leader>ft")
vim.keymap.del({ "n", "t" }, "<c-/>")
vim.keymap.del({ "n", "t" }, "<c-_>")
vim.keymap.set("n", "<leader>ft", ":ToggleTerm<cr>", { desc = "Toggle the buitin terminal" })
