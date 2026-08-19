-- storyteller.keymaps
-- Optional keybindings under the `<leader>s` namespace, with a which-key
-- "Story" group when which-key is present.

local M = {}

local keymaps = {}

M.register = function(lhs, rhs, desc)
  keymaps[#keymaps + 1] = { lhs = lhs, rhs = rhs, desc = desc }
end

M.apply = function()
  for _, km in ipairs(keymaps) do
    vim.keymap.set("n", km.lhs, km.rhs, { desc = km.desc, silent = true })
  end
  local ok, wk = pcall(require, "which-key")
  if ok then
    local spec = { { "<leader>s", group = "Story" } }
    for _, km in ipairs(keymaps) do
      spec[#spec + 1] = { km.lhs, desc = km.desc }
    end
    wk.add(spec)
  end
end

M.ensure = function()
  if M._applied then
    return
  end
  M.apply()
  M._applied = true
end

M.reset = function()
  M._applied = false
end

return M
