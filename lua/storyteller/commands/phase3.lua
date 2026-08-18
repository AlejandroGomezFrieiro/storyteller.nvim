-- storyteller.commands.phase3
-- Phase 3 commands:
--   :StoryDetect        reference detection across the whole project
--                        (auto-links high-confidence suggestions)
--   :StoryDetectScene   reference detection for the scene under the cursor
--   :StoryReferences    browse reference cards grouped by type
--   :StoryCorkboard     open the scene corkboard for the current project
--
-- Idempotent: re-registering the same command names simply replaces the
-- handlers in the shared `storyteller.command` registry.

local project = require("storyteller.project")
local index = require("storyteller.index")
local detect = require("storyteller.detect")
local references = require("storyteller.references")
local corkboard = require("storyteller.corkboard")
local command = require("storyteller.command")

local M = {}

local function current_prj()
  local prj = project.current()
  if not prj then
    vim.notify("[storyteller] Not in a storytelling project.", vim.log.levels.WARN)
    return nil
  end
  return prj
end

local function current_scene(prj)
  local file = vim.fn.expand("%:p")
  local line = vim.api.nvim_win_get_cursor(0)[1]
  for _, sc in ipairs(index.scenes(prj)) do
    if sc.path == file and sc.start_line <= line and line <= (sc.end_line or math.huge) then
      return sc
    end
  end
  return nil
end

-- Run detection across every scene; auto-link confident suggestions.
local function run_detect(prj)
  local results = detect.detect_project(prj)
  local total, linked = 0, 0
  for _, sugs in pairs(results) do
    total = total + #sugs
    for _, s in ipairs(sugs) do
      if s.confidence >= 0.9 then
          detect.link(s.scene, s.reference)
        linked = linked + 1
      end
    end
  end
  vim.notify(
    ("[storyteller] Detected %d suggestion(s); auto-linked %d confident match(es)."):format(total, linked),
    vim.log.levels.INFO
  )
end

M.setup = function()
  command.register("Detect", function(_)
    local prj = current_prj()
    if prj then
      run_detect(prj)
    end
  end, { desc = "Detect references across the project", opts = { nargs = 0 } })

  command.register("DetectScene", function(_)
    local prj = current_prj()
    if not prj then
      return
    end
    local sc = current_scene(prj)
    if not sc then
      vim.notify("[storyteller] No scene under the cursor.", vim.log.levels.WARN)
      return
    end
    references.suggest(sc, prj)
  end, { desc = "Detect references in the current scene", opts = { nargs = 0 } })

  command.register("References", function(_)
    local prj = current_prj()
    if prj then
      references.panel(prj)
    end
  end, { desc = "Browse reference cards by type", opts = { nargs = 0 } })

  command.register("Corkboard", function(args)
    local prj = current_prj()
    if prj then
      corkboard.open(prj, args.fargs and args.fargs[1])
    end
  end, { desc = "Open the scene corkboard", opts = { nargs = "?" } })
end

return M
