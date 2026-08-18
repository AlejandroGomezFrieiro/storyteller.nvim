-- storyteller — main entry point.
--
-- A Scrivener/Kindling-class novel-writing engine over Markdown.
--   require("storyteller").setup({ ... })
--
-- Contract surface (frozen so parallel subagents can build against it):
--   * storyteller.project   -> project.lua   { find_root(), paths, ... }
--   * storyteller.metadata  -> metadata.lua  { get/set_* on buffers/paths }
--   * storyteller.pickers   -> pickers/init  { pick(kind, ...) }
--   * storyteller.status    -> (Phase 1)     pure data for lualine

local config = require("storyteller.config")
local project = require("storyteller.project")
local events = require("storyteller.events")

local M = {}

M.setup = function(opts)
  config.setup(opts)

  -- Detect the current project lazily; cache it per directory.
  project.setup()

  -- Register :Story* user commands (Phase 0 defaults + any phase additions).
  require("storyteller.commands.phase0").setup()
  require("storyteller.command").setup()

  -- Autocmds: enter a buffer -> attach project + optional detect-on-save.
  if config.get().autocmds then
    events.setup()
  end

  -- Optional keymaps/which-key surface inside a project.
  require("storyteller.keymaps").ensure()

  -- Phase 1+: load outline/status lazily (guarded here so old loaders work).
  -- (Phase 1 modules register via the same command registry.)

  return M
end

-- Conveniences so consumers don't reach into internals everywhere.
M.get_project = function()
  return project.current()
end

M.config = config

return M