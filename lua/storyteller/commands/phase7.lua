local command = require("storyteller.command")
local workflow = require("storyteller.workflow")
local project = require("storyteller.project")
local resume = require("storyteller.resume")

local function filters(args)
  local out = {}
  for _, arg in ipairs(args.fargs or {}) do
    local key, value = arg:match("^([%w_]+)=(.+)$")
    if key then out[key] = value end
  end
  return out
end

return {
  setup = function()
    command.register("ScenePick", function() workflow.pick() end, { desc = "Pick a scene", opts = { nargs = 0 } })
    command.register("SceneNext", function() workflow.move(1) end, { desc = "Next scene", opts = { nargs = 0 } })
    command.register("ScenePrevious", function() workflow.move(-1) end, { desc = "Previous scene", opts = { nargs = 0 } })
    command.register("Continuity", function(args) workflow.continuity(project.current(), filters(args)) end, { desc = "Open continuity matrix", opts = { nargs = "*" } })
    command.register("Revision", function(args) workflow.revision(project.current(), args.fargs and args.fargs[1]) end, { desc = "Open revision queue", opts = { nargs = "?" } })
    command.register("Context", function() workflow.context() end, { desc = "Open drafting context", opts = { nargs = 0 } })
    command.register("Idea", function() workflow.idea() end, { desc = "Capture discovery idea", opts = { nargs = 0 } })
    command.register("Discoveries", function() workflow.discoveries() end, { desc = "Review discovery ideas", opts = { nargs = 0 } })
    command.register("Resume", function() resume.open() end, { desc = "Resume last scene", opts = { nargs = 0 } })
  end,
}
