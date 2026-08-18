-- storyteller.config
-- User-facing defaults and option resolution. `setup(opts)` merges opts on top.

local M = {}

local DEFAULTS = {
  -- How the project root is detected (in order of preference).
  markers = { ".storyteller", ".storyteller.toml" },
  -- Optional user override dir for story-structure templates (`templates_dir/`).
  templates_dir = nil,
  -- Whether autocmds auto-run for markdown files inside a project.
  autocmds = true,
  -- Detection: auto-run reference detection on save for the current scene.
  detect_on_save = true,
  detect_debounce = 300, -- ms
  -- Picker backend: "telescope" | "fzf" | "auto".
  picker = "auto",
  -- Per-text-width column for prose (used for a status hint).
  target_icon = "🎯",
  -- Collections: which predicates to expose as quick filters.
  collections = {
    predicates = {
      "pov",
      "location",
      "status",
      "planning",
      "unfinished",
      "tagged",
    },
  },
  -- Binaries used (optional). Falls back to vim glob/systemlist otherwise.
  rg = vim.fn.executable("rg") == 1 and "rg" or nil,
  pandoc = vim.fn.executable("pandoc") == 1 and "pandoc" or nil,
  status = {
    -- Extra status fields surfaced to lualine.
    show_session = true,
    show_target = true,
  },
}

M.defaults = function()
  return vim.deepcopy(DEFAULTS)
end

M.setup = function(opts)
  opts = opts or {}
  M.user = vim.tbl_deep_extend("force", M.user or M.defaults(), opts)
  return M.user
end

M.get = function()
  if not M.user then
    M.setup()
  end
  return M.user
end

return M
