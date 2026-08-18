-- Shared git helpers for the branch-review keymaps (<leader>gR / <leader>gD)
local M = {}

---Git repo root containing `dir`, or nil if it isn't inside a repo
---@param dir string
---@return string|nil
function M.root_of(dir)
  local root = vim.fn.systemlist({ "git", "-C", dir, "rev-parse", "--show-toplevel" })[1]
  if vim.v.shell_error ~= 0 or not root or root == "" then
    return nil
  end
  return root
end

---Repo root for the current buffer's file, falling back to the cwd
---@return string|nil
function M.buffer_root()
  local dir = vim.fn.expand("%:p:h")
  if dir == "" or dir:find("://", 1, true) then
    dir = vim.fn.getcwd()
  end
  return M.root_of(dir)
end

---Best-guess base ref for reviews in `root`, e.g. "origin/main".
---origin/HEAD is only set by clone, so fall back to probing common bases.
---@param root string
---@return string
function M.default_base(root)
  local head = vim.fn.systemlist({ "git", "-C", root, "symbolic-ref", "--short", "refs/remotes/origin/HEAD" })[1]
  if vim.v.shell_error == 0 and head and head ~= "" then
    return head
  end
  for _, ref in ipairs({ "origin/main", "origin/master", "main", "master" }) do
    vim.fn.systemlist({ "git", "-C", root, "rev-parse", "--verify", "--quiet", ref })
    if vim.v.shell_error == 0 then
      return ref
    end
  end
  return "main"
end

return M
