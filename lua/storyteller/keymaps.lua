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
    -- which-key v3 expects a list of mapping specs, not a dictionary keyed by
    -- lhs. The maps themselves are defined above; these entries only provide
    -- group/description metadata for the popup.
    local spec = { { "<leader>s", group = "Writing" } }
    for _, km in ipairs(keymaps) do
      table.insert(spec, { km.lhs, desc = km.desc })
    end
    wk.add(spec)
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
