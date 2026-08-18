-- storyteller.keymaps
-- Optional keybindings. Applied only when a project is detected, under the
-- which-key "Writing" group when which-key is present.

local M = {}

-- { lhs, rhs, desc } ; `<leader>s*` namespace.
local keymaps = {}

M.register = function(lhs, rhs, desc)
  keymaps[#keymaps + 1] = { lhs = lhs, rhs = rhs, desc = desc }
end

local function has(mod)
  return pcall(require, mod)
end

-- Apply all registered keymaps + which-key groups.
M.apply = function()
  for _, km in ipairs(keymaps) do
    vim.keymap.set("n", km.lhs, km.rhs, { desc = km.desc, silent = true })
  end
  if has "which-key" then
    local wk = require "which-key"
    local groups = {}
    for _, km in ipairs(keymaps) do
      local prefix = km.lhs:match("^<leader>(%a)<.*>$") or km.lhs:match("^<leader>(%a)")
      if prefix and not groups[prefix] then
        groups[prefix] = { prefix .. " → Writing" }
      end
    end
    -- register the Writing group once
    local grouptable = {}
    for _, km in ipairs(keymaps) do
      local short = km.lhs:gsub("^<leader>", "<leader>")
      grouptable[short] = { km.desc }
    end
    wk.add(grouptable)
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