-- storyteller.commands.phase5
-- Phase 5 commands: templates + export.
--   :StoryTemplate            pick and apply a story structure
--   :StoryExport [fmt]        export the current manuscript (whole project)
--   :StoryExportAll [fmt]     export every chapter to the build dir

local project = require("storyteller.project")
local pickers = require("storyteller.pickers")
local command = require("storyteller.command")
local templates = require("storyteller.templates")
local export = require("storyteller.export")

local M = {}

local function current_prj()
  local prj = project.current()
  if not prj then
    vim.notify("[storyteller] Not in a storytelling project.", vim.log.levels.WARN)
    return nil
  end
  return prj
end

local function fmt_from_arg(args)
  local fargs = args and args.fargs or {}
  return fargs[1]
end

local function setup_phase5()
  command.register("Template", function()
    local prj = current_prj()
    if not prj then
      return
    end
    local entries = templates.entries()
    if #entries == 0 then
      vim.notify("[storyteller] No story templates found.", vim.log.levels.WARN)
      return
    end
    pickers.pick_list(entries, {
      prompt_title = "Storyteller templates",
      on_select = function(entry)
        templates.apply(prj, entry.id)
      end,
    })
  end, { desc = "Pick and apply a story structure", opts = {} })

  command.register("Export", function(args)
    local prj = current_prj()
    if not prj then
      return
    end
    local out = export.export_manuscript(prj, fmt_from_arg(args))
    if out then
      vim.notify(("[storyteller] Exported manuscript → %s"):format(out), vim.log.levels.INFO)
    end
  end, { desc = "Export manuscript (docx, epub, pdf, smf)", opts = { nargs = "*" } })

  command.register("ExportAll", function(args)
    local prj = current_prj()
    if not prj then
      return
    end
    local out = export.export_manuscript(prj, fmt_from_arg(args))
    if out then
      vim.notify(("[storyteller] Exported project → %s"):format(out), vim.log.levels.INFO)
    end
  end, { desc = "Export the whole compiled project", opts = { nargs = "*" } })
end

M.setup = function()
  setup_phase5()
end

return M