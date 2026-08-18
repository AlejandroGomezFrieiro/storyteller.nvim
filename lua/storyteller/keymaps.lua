-- storyteller.keymaps
-- Optional keybindings. Applied only when a project is detected, under the
-- which-key "Writing" group when which-key is present.

local M = {}

-- { lhs, rhs, desc } ; `<leader>s*` namespace.
local keymaps = {}

M.register = function(lhs, rhs, desc)
  keymaps[#keymaps + 1] = { lhs = lhs, rhs = rhs, desc = desc }
end

-- Apply all registered keymaps + which-key group.
M.apply = function()
  for _, km in ipairs(keymaps) do
    vim.keymap.set("n", km.lhs, km.rhs, { desc = km.desc, silent = true })
  end
  local ok, wk = pcall(require, "which-key")
  if ok then
    wk.add({ { "<leader>s", group = "Writing" } })
    local mappings = {}
    for _, km in ipairs(keymaps) do
      mappings[km.lhs] = { km.desc }
    end
    wk.add(mappings)
  end
end

-- Only meaningful inside a project; called after project detection.
M.ensure = function()
  -- registered keymaps are applied once; guard against duplication
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