-- storyteller.ui.dashboard
-- The entry screen: project stats plus one row per pillar. Selecting a row
-- runs the corresponding view/command.

local ui = require("storyteller.ui")
local project = require("storyteller.project")
local index = require("storyteller.index")
local track = require("storyteller.track")
local compile = require("storyteller.compile")

local M = {}

local function run(fn)
  fn()
end

function M.open(prj)
  prj = prj or project.current()
  ui.view({
    name = "dashboard",
    prj = prj,
    build = function()
      local views = require("storyteller.ui.views")
      local references = require("storyteller.references")
      local templates = require("storyteller.templates")
      local pickers = require("storyteller.pickers")

      local lines = {
        { text = "STORYTELLER", hl = "StorytellerTitle" },
        { text = "<CR> run · q close", hl = "StorytellerMuted" },
        { text = "", hl = nil },
      }
      local chapters = index.chapters(prj)
      local scenes = index.scenes(prj)
      lines[#lines + 1] = {
        text = ("%d chapters · %d scenes · %d words"):format(#chapters, #scenes, track.total_words(prj)),
        hl = "StorytellerMetric",
      }
      local s = track.streaks(prj)
      lines[#lines + 1] = { text = ("Streak: %d days"):format(s.current), hl = "StorytellerMetric" }
      lines[#lines + 1] = { text = "", hl = nil }

      local function template_pick()
        local entries = templates.entries()
        if #entries == 0 then
          vim.notify("[storyteller] No story templates found.", vim.log.levels.WARN)
          return
        end
        pickers.pick_list(entries, {
          prompt_title = "Storyteller templates",
          on_select = function(entry)
            views.template_preview(prj, entry.id)
          end,
        })
      end

      local actions = {
        { key = "o", name = "Outline", run = function() views.outline(prj) end },
        { key = "b", name = "Corkboard", run = function() views.corkboard(prj) end },
        { key = "c", name = "Compile (Scrivenings)", run = function() compile.open(prj) end },
        { key = "t", name = "Tracking", run = function() views.track(prj) end },
        { key = "T", name = "Apply a story template", run = template_pick },
        { key = "e", name = "Export manuscript", run = function() require("storyteller.commands").dispatch(prj, { "export" }) end },
        { key = "r", name = "References", run = function() references.panel(prj) end },
        { key = "d", name = "Detect references", run = function() require("storyteller.commands").dispatch(prj, { "detect" }) end },
        { key = "m", name = "Edit scene metadata", run = function() require("storyteller.ui.meta_form").edit(index.current_scene(prj)) end },
        { key = "w", name = "Workspace", run = function() require("storyteller.ui.workspace").toggle(prj) end },
      }

      local select = {}
      for _, a in ipairs(actions) do
        lines[#lines + 1] = { text = ("[%s] %s"):format(a.key, a.name), hl = "StorytellerScene" }
        select[#lines] = a.run
      end
      return { lines = lines, select = select }
    end,
    on_select = run,
  })
end

return M
