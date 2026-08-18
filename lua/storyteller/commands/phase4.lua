-- storyteller.commands.phase4
-- Phase 4 commands: targets dashboard, sessions, progress log, snapshots.

local project = require("storyteller.project")
local target = require("storyteller.target")
local snapshot = require("storyteller.snapshot")
local command = require("storyteller.command")
local pickers = require("storyteller.pickers")

local M = {}

local function current_prj()
  local prj = project.current()
  if not prj then
    vim.notify("[storyteller] Not in a storytelling project.", vim.log.levels.WARN)
    return nil
  end
  return prj
end

M.setup = function()
  command.register("Targets", function(_)
    target.dashboard(current_prj())
  end, { desc = "Open the targets/dashboard report", opts = { nargs = 0 } })

  command.register("SessionStart", function(_)
    target.session_start()
  end, { desc = "Begin a writing session counter", opts = { nargs = 0 } })

  command.register("SessionEnd", function(_)
    target.session_end()
  end, { desc = "End the session and log today's progress", opts = { nargs = 0 } })

  command.register("Progress", function(_)
    target.progress_append(current_prj())
  end, { desc = "Append/update today's delta in progress.log", opts = { nargs = 0 } })

  command.register("Snapshot", function(args)
    local prj = current_prj()
    if prj then
      snapshot.snapshot(prj, args and args.fargs and args.fargs[1])
    end
  end, { desc = "Commit a snapshot of the whole project", opts = { nargs = "?" } })

  command.register("Snapshots", function(_)
    local prj = current_prj()
    if not prj then
      return
    end
    local snaps = snapshot.list(prj)
    if #snaps == 0 then
      vim.notify("[storyteller] No snapshots yet.", vim.log.levels.INFO)
      return
    end
    local entries = {}
    for _, s in ipairs(snaps) do
      table.insert(entries, { value = s, display = tostring(s) })
    end
    pickers.pick_list(entries, {
      prompt_title = "Storyteller snapshots",
      on_select = function() end, -- informational pick
    })
  end, { desc = "List project snapshots", opts = { nargs = 0 } })
end

return M