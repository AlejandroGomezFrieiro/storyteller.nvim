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
  if M._initialized then
    return M
  end

  -- Detect the current project lazily; cache it per directory.
  project.setup()

  -- Register :Story* user commands (Phase 0 defaults + any phase additions).
  require("storyteller.commands.phase0").setup()
  require("storyteller.commands.phase1").setup()
  require("storyteller.commands.phase2").setup()
  require("storyteller.commands.phase3").setup()
  require("storyteller.commands.phase4").setup()
  require("storyteller.commands.phase5").setup()
  require("storyteller.commands.phase7").setup()
  require("storyteller.command").setup()

  -- Autocmds: enter a buffer -> attach project + optional detect-on-save.
  if config.get().autocmds then
    events.setup()
  end

  -- Optional keymaps/which-key surface inside a project.
  local km = require("storyteller.keymaps")
  km.register("<leader>so", "<cmd>StoryOutline<cr>", "Outline")
  km.register("<leader>ss", "<cmd>StoryScrivenings<cr>", "Scrivenings")
  km.register("<leader>sr", "<cmd>StoryReferences<cr>", "References")
  km.register("<leader>sd", "<cmd>StoryDetectScene<cr>", "Detect refs in scene")
  km.register("<leader>sb", "<cmd>StoryCorkboard<cr>", "Corkboard")
  km.register("<leader>st", "<cmd>StoryTargets<cr>", "Targets")
  km.register("<leader>sn", "<cmd>StorySnapshot<cr>", "Snapshot")
  km.register("<leader>sx", "<cmd>StoryExport<cr>", "Export")
  km.register("<leader>sT", "<cmd>StoryTemplate<cr>", "Template")
  km.register("<leader>sp", "<cmd>StoryScenePick<cr>", "Pick scene")
  km.register("<leader>sc", "<cmd>StoryContinuity<cr>", "Continuity")
  km.register("<leader>sv", "<cmd>StoryRevision<cr>", "Revision queue")
  km.register("<leader>sC", "<cmd>StoryContext<cr>", "Drafting context")
  km.register("<leader>si", "<cmd>StoryIdea<cr>", "Capture idea")
  km.register("<leader>sl", "<cmd>StoryResume<cr>", "Resume last scene")
  km.ensure()

  M._initialized = true
  return M
end

-- Conveniences so consumers don't reach into internals everywhere.
M.get_project = function()
  return project.current()
end

M.config = config

return M
