-- storyteller.commands.phase1
-- Phase 1 commands: enhanced interactive outline with targets/progress.

local outline = require("storyteller.outline")
local command = require("storyteller.command")

local M = {}

M.setup = function()
  -- Override the Phase 0 Outline with the richer project outline picker.
  command.register("Outline", function(_)
    outline.pick()
  end, { desc = "Project outline with word targets", opts = { nargs = 0 } })
end

return M