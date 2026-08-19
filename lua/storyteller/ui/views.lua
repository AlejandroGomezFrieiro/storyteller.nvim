-- storyteller.ui.views
-- Concrete views: outline, corkboard, tracking dashboard, binder, inspector.
-- Each builds `lines` + a `select` map and hands them to `ui.view`.

local index = require("storyteller.index")
local meta = require("storyteller.meta")
local track = require("storyteller.track")
local schema = require("storyteller.schema")
local ui = require("storyteller.ui")
local pickers = require("storyteller.pickers")
local project = require("storyteller.project")

local M = {}

local function bar(pct)
  pct = math.max(0, math.min(100, pct or 0))
  local filled = math.floor(pct / 10)
  return string.rep("█", filled) .. string.rep("░", 10 - filled)
end

local function edit(path)
  vim.cmd("edit " .. vim.fn.fnameescape(path))
end

local function scene_status(sc)
  return meta.field(sc, "status", "outline")
end

-- Cycle the status of a scene (or a chapter, when the row is a chapter).
local function cycle_status(data)
  if data.start_line then
    local current = scene_status(data)
    meta.scene_write(data, { status = schema.next_status(current) })
  else
    local doc = meta.chapter(data.path)
    local current = (doc and doc.meta.status) or "outline"
    meta.chapter_write(data.path, { status = schema.next_status(current) })
  end
  local buf = vim.api.nvim_get_current_buf()
  local fn = vim.b[buf].storyteller_refresh
  if fn then
    fn()
  end
end

-- --- Outline ----------------------------------------------------------------

function M.outline(prj)
  prj = prj or project.current()
  ui.view({
    name = "outline",
    prj = prj,
    build = function()
      local lines = {
        { text = "OUTLINE — " .. vim.fn.fnamemodify(prj.root, ":t"), hl = "StorytellerTitle" },
        { text = "<CR> open · a status · R refresh · q close", hl = "StorytellerMuted" },
      }
      local select = {}
      for _, ch in ipairs(index.chapters(prj)) do
        local words = index.chapter_words(ch)
        local target = ch.target or 0
        local pct = target > 0 and math.floor(words / target * 100) or 0
        local text = ("%-34s %6d w  %s %3d%%"):format(ch.title or ch.filename, words, bar(pct), pct)
        lines[#lines + 1] = { text = text, hl = "StorytellerScene" }
        select[#lines] = ch
      end
      return { lines = lines, select = select }
    end,
    on_select = function(ch)
      edit(ch.path)
    end,
    keys = { a = function()
      local sel = vim.b[vim.api.nvim_get_current_buf()].storyteller_select
      local data = sel[vim.api.nvim_win_get_cursor(0)[1]]
      if data then
        cycle_status(data)
      end
    end },
  })
end

-- --- Scene picker -----------------------------------------------------------

function M.scenes(prj)
  prj = prj or project.current()
  local entries = {}
  for _, sc in ipairs(index.scenes(prj)) do
    entries[#entries + 1] = {
      value = sc,
      display = ("%s · %s · %d w"):format(
        sc.chapter and (sc.chapter.title or vim.fn.fnamemodify(sc.path, ":t:r")) or "",
        sc.title or "(untitled)",
        sc.words or 0
      ),
    }
  end
  pickers.pick_list(entries, {
    prompt_title = "Story scenes",
    on_select = function(sc)
      index.open_scene(sc)
    end,
  })
end

function M.next(delta, prj)
  prj = prj or project.current()
  local active = index.current_scene(prj)
  if not active then
    return M.scenes(prj)
  end
  local all = index.scenes(prj)
  for i, sc in ipairs(all) do
    if sc.path == active.path and sc.start_line == active.start_line then
      local target = all[i + delta]
      if target then
        index.open_scene(target)
      end
      return
    end
  end
end

-- --- Corkboard --------------------------------------------------------------

function M.corkboard(prj, filter)
  prj = prj or project.current()
  ui.view({
    name = "corkboard",
    prj = prj,
    build = function()
      local lines = {
        { text = "CORKBOARD — " .. vim.fn.fnamemodify(prj.root, ":t"), hl = "StorytellerTitle" },
        { text = "<CR> open · a status · u unused · R refresh · q close", hl = "StorytellerMuted" },
      }
      local select = {}
      local lf = filter and filter:lower() or ""
      for _, sc in ipairs(index.scenes(prj)) do
        local info = meta.scene(sc)
        local status = info.meta.status or "outline"
        local pov = info.meta.pov or "?"
        local loc = info.meta.location
        local label = ("%-28s · %-12s · %4d w%s"):format(
          sc.title or "(untitled)",
          pov,
          sc.words or 0,
          loc and (" · " .. loc) or ""
        )
        if lf == "" or label:lower():find(lf, 1, true) then
          lines[#lines + 1] = { text = label, hl = ui.status_hl(status) or "StorytellerScene" }
          select[#lines] = sc
        end
      end
      return { lines = lines, select = select }
    end,
    on_select = function(sc)
      index.open_scene(sc)
    end,
    keys = {
      a = function()
        local sel = vim.b[vim.api.nvim_get_current_buf()].storyteller_select
        local sc = sel[vim.api.nvim_win_get_cursor(0)[1]]
        if sc then
          cycle_status(sc)
        end
      end,
      u = function()
        local sel = vim.b[vim.api.nvim_get_current_buf()].storyteller_select
        local sc = sel[vim.api.nvim_win_get_cursor(0)[1]]
        if sc then
          meta.scene_write(sc, { status = "unused" })
          local fn = vim.b[vim.api.nvim_get_current_buf()].storyteller_refresh
          if fn then
            fn()
          end
        end
      end,
    },
  })
end

-- --- Tracking dashboard -----------------------------------------------------

function M.track(prj)
  prj = prj or project.current()
  ui.view({
    name = "track",
    prj = prj,
    build = function()
      local lines = {
        { text = "TRACKING — " .. vim.fn.fnamemodify(prj.root, ":t"), hl = "StorytellerTitle" },
        { text = "<CR> open chapter · s session · p progress · R refresh · q close", hl = "StorytellerMuted" },
      }
      local select = {}
      lines[#lines + 1] = { text = ("Total words: %d"):format(track.total_words(prj)), hl = "StorytellerMetric" }
      local streaks = track.streaks(prj)
      lines[#lines + 1] = { text = ("Streak: %d current · %d longest"):format(streaks.current, streaks.longest), hl = "StorytellerMetric" }
      lines[#lines + 1] = { text = "", hl = nil }

      lines[#lines + 1] = { text = "CHAPTERS", hl = "StorytellerSection" }
      local sum = 0
      for _, ch in ipairs(index.chapters(prj)) do
        local words = index.chapter_words(ch)
        local target = ch.target or 0
        sum = sum + target
        local pct = target > 0 and math.floor(words / target * 100) or 0
        lines[#lines + 1] = {
          text = ("%-34s %s %3d%%  %d/%d"):format(ch.title or ch.filename, bar(pct), pct, words, target),
          hl = "StorytellerScene",
        }
        select[#lines] = ch
      end
      if sum > 0 then
        lines[#lines + 1] = { text = ("Manuscript target: %d"):format(sum), hl = "StorytellerMuted" }
      end

      local s = track.session_stats()
      if s then
        lines[#lines + 1] = { text = "", hl = nil }
        lines[#lines + 1] = { text = ("Session: +%d words since %s"):format(s.written, s.started_at), hl = "StorytellerMetric" }
      end

      lines[#lines + 1] = { text = "", hl = nil }
      lines[#lines + 1] = { text = "ACTIVITY", hl = "StorytellerSection" }
      local heat = track.heatmap(prj, require("storyteller.config").get().heatmap_weeks)
      for _, hline in ipairs(ui.heatmap_lines(heat)) do
        lines[#lines + 1] = { text = hline, hl = "StorytellerMetric" }
      end

      lines[#lines + 1] = { text = "", hl = nil }
      lines[#lines + 1] = { text = "MILESTONES", hl = "StorytellerSection" }
      for _, m in ipairs(track.milestones(prj)) do
        lines[#lines + 1] = {
          text = ("%s %s"):format(m.done and "●" or "○", m.name),
          hl = m.done and "StorytellerDone" or "StorytellerOutline",
        }
      end

      return { lines = lines, select = select }
    end,
    on_select = function(ch)
      edit(ch.path)
    end,
    keys = {
      s = function()
        if vim.g.storyteller_session then
          track.session_end()
        else
          track.session_start()
        end
        local fn = vim.b[vim.api.nvim_get_current_buf()].storyteller_refresh
        if fn then
          fn()
        end
      end,
      p = function()
        track.progress_append(prj)
        local fn = vim.b[vim.api.nvim_get_current_buf()].storyteller_refresh
        if fn then
          fn()
        end
      end,
    },
  })
end

-- --- Binder (chapter -> scene tree) ----------------------------------------

function M.binder(prj)
  prj = prj or project.current()
  ui.view({
    name = "binder",
    prj = prj,
    build = function()
      local lines = {
        { text = "BINDER", hl = "StorytellerTitle" },
        { text = "<CR> open · R refresh · q close", hl = "StorytellerMuted" },
      }
      local select = {}
      for _, ch in ipairs(index.chapters(prj)) do
        lines[#lines + 1] = { text = "▸ " .. (ch.title or ch.filename), hl = "StorytellerSection" }
        select[#lines] = ch
        for _, sc in ipairs(ch.scenes) do
          local status = scene_status(sc)
          lines[#lines + 1] = {
            text = ("    %s"):format(sc.title or "(untitled)"),
            hl = ui.status_hl(status) or "StorytellerScene",
          }
          select[#lines] = sc
        end
      end
      return { lines = lines, select = select }
    end,
    on_select = function(data)
      if data.start_line then
        index.open_scene(data)
      else
        edit(data.path)
      end
    end,
  })
end

-- --- Inspector (current scene metadata) -------------------------------------

function M.inspector(prj)
  prj = prj or project.current()
  local scene = index.current_scene(prj)
  if not (prj and scene) then
    vim.notify("[storyteller] No scene under the cursor.", vim.log.levels.WARN)
    return nil
  end
  ui.view({
    name = "inspector",
    prj = prj,
    build = function()
      local info = meta.scene(scene)
      local m = info.meta
      local lines = {
        { text = (scene.title or "SCENE"):upper(), hl = "StorytellerTitle" },
        { text = "<CR> open reference · m edit meta · R refresh · q close", hl = "StorytellerMuted" },
        { text = "", hl = nil },
        { text = ("Status: %s | POV: %s | Location: %s"):format(m.status or "outline", m.pov or "?", m.location or "?"), hl = "StorytellerScene" },
        { text = ("Time: %s"):format(m.time or "?"), hl = "StorytellerMuted" },
        { text = "", hl = nil },
        { text = "BEAT", hl = "StorytellerSection" },
        { text = tostring(m.beat or "No beat recorded."), hl = nil },
        { text = "", hl = nil },
        { text = "GOAL / CONFLICT / OUTCOME", hl = "StorytellerSection" },
        { text = tostring(m.goal or "—"), hl = nil },
        { text = tostring(m.conflict or "—"), hl = nil },
        { text = tostring(m.outcome or "—"), hl = nil },
      }
      return { lines = lines, select = {} }
    end,
    keys = {
      m = function()
        require("storyteller.ui.meta_form").edit(scene)
      end,
    },
  })
end

-- --- Template preview -------------------------------------------------------

function M.template_preview(prj, name)
  local templates = require("storyteller.templates")
  local plan = templates.plan(prj, name)
  if not plan then
    vim.notify("[storyteller] Unknown template: " .. tostring(name), vim.log.levels.ERROR)
    return
  end
  ui.view({
    name = "template-preview",
    prj = prj,
    build = function()
      local lines = {
        { text = ("TEMPLATE: %s"):format(plan.template.name or plan.template.id), hl = "StorytellerTitle" },
        { text = "a apply · q cancel", hl = "StorytellerMuted" },
        { text = "", hl = nil },
        { text = ("%d chapter(s) to create · %d skipped"):format(#plan.created, #plan.skipped), hl = "StorytellerMetric" },
      }
      for _, p in ipairs(plan.created) do
        lines[#lines + 1] = { text = ("  + %s"):format(vim.fn.fnamemodify(p, ":t")), hl = "StorytellerDone" }
      end
      for _, p in ipairs(plan.skipped) do
        lines[#lines + 1] = { text = ("  = %s (exists)"):format(vim.fn.fnamemodify(p, ":t")), hl = "StorytellerMuted" }
      end
      return { lines = lines, select = {} }
    end,
    keys = {
      a = function()
        templates.apply(prj, name)
        vim.cmd("close")
      end,
    },
  })
end

return M
