-- storyteller — main entry point.
--
--   require("storyteller").setup({ ... })
--
-- A Scrivener/Kindling-class writing engine over Markdown, organized around
-- five pillars: metadata, compilation, tracking, templating, and UI.

local config = require("storyteller.config")
local project = require("storyteller.project")
local events = require("storyteller.events")

local M = {}

M.setup = function(opts)
  config.setup(opts)
  if M._initialized then
    return M
  end

  project.setup()

  require("storyteller.commands").setup()

  if config.get().autocmds then
    events.setup()
  end

  local km = require("storyteller.keymaps")
  km.register("<leader>s", "<cmd>Story<cr>", "Dashboard")
  km.register("<leader>so", "<cmd>Story outline<cr>", "Outline")
  km.register("<leader>sn", "<cmd>Story next<cr>", "Next scene")
  km.register("<leader>sp", "<cmd>Story prev<cr>", "Previous scene")
  km.register("<leader>sb", "<cmd>Story corkboard<cr>", "Corkboard")
  km.register("<leader>sm", "<cmd>Story meta<cr>", "Edit scene metadata")
  km.register("<leader>ss", "<cmd>Story status<cr>", "Cycle scene status")
  km.register("<leader>sc", "<cmd>Story compile<cr>", "Compile manuscript")
  km.register("<leader>st", "<cmd>Story track<cr>", "Tracking")
  km.register("<leader>sd", "<cmd>Story detect<cr>", "Detect references")
  km.register("<leader>sr", "<cmd>Story references<cr>", "References")
  km.register("<leader>sl", "<cmd>Story resume<cr>", "Resume last scene")
  km.register("<leader>se", "<cmd>Story export<cr>", "Export")
  km.register("<leader>sT", "<cmd>Story template<cr>", "Template")
  km.register("<leader>sw", "<cmd>Story workspace<cr>", "Workspace")
  km.register("<leader>si", "<cmd>Story idea<cr>", "Capture idea")
  km.ensure()

  -- Visual-mode: create a reference card from the selection.
  vim.keymap.set("v", "<leader>sr", function()
    require("storyteller.capture").run()
  end, { desc = "Create reference card from selection", silent = true })

  M._initialized = true
  return M
end

M.get_project = function()
  return project.current()
end

M.config = config

return M
