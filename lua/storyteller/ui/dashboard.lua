-- storyteller.ui.dashboard
-- The entry screen, in the spirit of triforce.nvim: a project header with
-- key metrics and a manuscript progress bar, a bordered stats grid, a
-- GitHub-style activity heatmap, grouped action panels, and milestones.

local ui = require("storyteller.ui")
local project = require("storyteller.project")
local index = require("storyteller.index")
local compile = require("storyteller.compile")

local M = {}

local function footer(text)
  return { text = "  " .. text, hl = "StorytellerMuted" }
end

local function action_row(action)
  return {
    segments = {
      { text = "[" .. action.key .. "] ", hl = "StorytellerKey" },
      { text = string.format("%-13s", action.name), hl = "StorytellerScene" },
    },
  }
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

      local lines = {}
      local select = {}

      for _, l in ipairs(views.header(prj, "STORYTELLER", "your writing room")) do
        lines[#lines + 1] = l
      end
      for _, l in ipairs(views.stats_table(prj)) do
        lines[#lines + 1] = l
      end
      lines[#lines + 1] = { text = "", hl = nil }
      for _, l in ipairs(views.activity_panel(prj)) do
        lines[#lines + 1] = l
      end
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

      local groups = {
        {
          title = "WRITE",
          actions = {
            {
              key = "C",
              name = "Compile",
              run = function()
                compile.open(prj)
              end,
            },
            {
              key = "E",
              name = "Export",
              run = function()
                require("storyteller.commands").dispatch(prj, { "export" })
              end,
            },
            {
              key = "S",
              name = "Session",
              run = function()
                require("storyteller.commands").dispatch(prj, { "session" })
              end,
            },
          },
        },
        {
          title = "NAVIGATE",
          actions = {
            {
              key = "O",
              name = "Outline",
              run = function()
                views.outline(prj)
              end,
            },
            {
              key = "B",
              name = "Corkboard",
              run = function()
                require("storyteller.ui.storyboard").open("corkboard", prj)
              end,
            },
            {
              key = "W",
              name = "Workspace",
              run = function()
                require("storyteller.ui.workspace").toggle(prj)
              end,
            },
          },
        },
        {
          title = "REVIEW",
          actions = {
            {
              key = "T",
              name = "Tracking",
              run = function()
                views.track(prj)
              end,
            },
            {
              key = "Y",
              name = "Timeline",
              run = function()
                require("storyteller.ui.storyboard").open("timeline", prj)
              end,
            },
            {
              key = "F",
              name = "Threads",
              run = function()
                views.threads(prj)
              end,
            },
          },
        },
      }
      local groups2 = {
        {
          title = "STORY",
          actions = {
            {
              key = "M",
              name = "Scene meta",
              run = function()
                require("storyteller.ui.meta_form").edit(index.current_scene(prj))
              end,
            },
            { key = "T", name = "Template", run = template_pick },
            {
              key = "H",
              name = "Health",
              run = function()
                views.health(prj)
              end,
            },
          },
        },
        {
          title = "ORGANIZE",
          actions = {
            {
              key = "R",
              name = "References",
              run = function()
                references.panel(prj)
              end,
            },
            {
              key = "D",
              name = "Detect",
              run = function()
                require("storyteller.commands").dispatch(prj, { "detect" })
              end,
            },
            {
              key = "I",
              name = "Ideas",
              run = function()
                require("storyteller.commands").dispatch(prj, { "idea" })
              end,
            },
          },
        },
      }

      local function render_groups(groups)
        local panels = {}
        for _, g in ipairs(groups) do
          local rows = {}
          for _, a in ipairs(g.actions) do
            rows[#rows + 1] = action_row(a)
          end
          panels[#panels + 1] = { title = g.title, rows = rows }
        end
        local panel_lines, bounds = ui.grid_panels(panels)
        local offset = #lines
        for _, l in ipairs(panel_lines) do
          lines[#lines + 1] = l
        end
        for r = 1, #groups[1].actions do
          select[offset + 1 + r] = function(col)
            local c = col + 1
            for i, b in ipairs(bounds) do
              if c >= b.start and c < b.start + b.width then
                return groups[i].actions[r]
              end
            end
            return nil
          end
        end
      end

      render_groups(groups)
      lines[#lines + 1] = { text = "", hl = nil }
      render_groups(groups2)
      lines[#lines + 1] = { text = "", hl = nil }
      for _, l in ipairs(views.milestones_panel(prj)) do
        lines[#lines + 1] = l
      end
      lines[#lines + 1] = { text = "", hl = nil }
      lines[#lines + 1] = footer("<CR> open   R refresh   q close")

      return { lines = lines, select = select }
    end,
    on_select = function(data)
      if type(data) == "function" then
        local _, col = vim.api.nvim_win_get_cursor(0)
        local action = data(col)
        if action then
          action.run()
        end
      end
    end,
  })
end

return M
