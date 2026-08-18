-- storyteller.commands.phase0
-- Default Phase 0 commands: Status + Outline. These depend only on the
-- Phase 0 contract (project, index, pickers). Later phases add their own
-- modules and register more commands.

local project = require("storyteller.project")
local index = require("storyteller.index")
local pickers = require("storyteller.pickers")
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

local function setup_phase0()
  command.register("Status", function(_)
    local prj = current_prj()
    if not prj then
      return
    end
    local chapters = index.chapters(prj)
    local scenes = index.scenes(prj)
    local refs = index.all_references(prj)
    local chapters_words = 0
    local targets = 0
    for _, ch in ipairs(chapters) do
      chapters_words = chapters_words + index.chapter_words(ch)
      targets = targets + (ch.target or 0)
    end
    vim.notify(
      ("%s chapters · %s scenes · %s words · %s reference cards\nTarget (sum) %s words")
        :format(
          #chapters,
          #scenes,
          chapters_words,
          #refs,
          targets
        ),
      vim.log.levels.INFO
    )
    -- set an event we can also read programmatically
    vim.g.storyteller_status = {
      chapters = #chapters,
      scenes = #scenes,
      words = chapters_words,
      references = #refs,
      target = targets,
    }
  end, { desc = "Show project stats", opts = {} })

  command.register("Outline", function(opts)
    local prj = current_prj()
    if not prj then
      return
    end
    local chapters = index.chapters(prj)
    local entries = {}
    for _, ch in ipairs(chapters) do
      local words = index.chapter_words(ch)
      local label = ("%02d %-28s %8d words"):format(ch.number or 0, ch.title or ch.filename, words)
      table.insert(entries, { value = ch, display = label })
    end
    pickers.pick_list(entries, {
      prompt_title = "Storyteller outline",
      on_select = function(ch)
        vim.cmd("edit " .. vim.fn.fnameescape(ch.path))
      end,
    })
  end, { desc = "Chapter outline with word counts", opts = { nargs = 0 } })
end

M.setup = function()
  setup_phase0()
end

return M