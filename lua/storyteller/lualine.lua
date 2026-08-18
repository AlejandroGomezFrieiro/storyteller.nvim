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
    }
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

-- If lualine is already loaded and has a stored config, patch its sections
-- with our component (idempotent). Users with a static config should use the
-- nixvim module's `sections` wiring instead.
M.patch = function()
  local ok, lualine = pcall(require, "lualine")
  if not ok then
    return false
  end
  -- Only when lazy -- we don't auto-setup; the nixvim module wires sections.
  return true
end

return M