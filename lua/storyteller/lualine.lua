-- storyteller.lualine
-- Lightweight lualine integration. lualine is optional; this module only
-- runs when lualine is actually present (checked by the caller).
--
-- Provides a ready-made component config and a helper to append it to the
-- current lualine setup without replacing user sections when possible.

local M = {}

-- The lualine "component" spec for storyteller's word/target section.
M.component = function()
  return {
    {
      function()
        return require("storyteller.status").render()
      end,
      color = { fg = "#f2cdcd" },
      cond = function()
        return vim.bo.filetype == "markdown"
      end,
    },
  }
end

-- Merge into an existing lualine `sections` table (append to z/b, best effort).
M.apply_to = function(sections)
  sections = sections or {}
  local comp = M.component()
  for _, key in ipairs({ "z", "y", "c" }) do
    if sections[key] then
      vim.list_extend(sections[key], comp)
      return sections
    end
  end
  -- fallback: no known slot, overwrite z
  sections.z = comp
  return sections
end

-- Lualine does not expose a stable public API for merging an already-applied
-- configuration, so callers should use `component()` or `apply_to()` before
-- calling lualine.setup(). Kept as a capability probe for compatibility.
M.patch = function()
  local ok = pcall(require, "lualine")
  if not ok then
    return false
  end
  return true
end

return M
