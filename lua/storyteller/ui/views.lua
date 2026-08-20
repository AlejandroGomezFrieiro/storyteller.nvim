-- storyteller.ui.views
-- Concrete views: dashboard panels, outline, corkboard, tracking, timeline,
-- plot threads, story health, binder, inspector. Each builds `lines` + a
-- `select` map and hands them to `ui.view`.
--
-- The visual language is inspired by triforce.nvim: titled bordered panels,
-- a bordered stats grid, segmented progress bars, and a GitHub-style
-- contribution heatmap with month and weekday labels.

local index = require("storyteller.index")
local meta = require("storyteller.meta")
local track = require("storyteller.track")
local schema = require("storyteller.schema")
local ui = require("storyteller.ui")
local pickers = require("storyteller.pickers")
local project = require("storyteller.project")

local M = {}

local PARTIAL = { " ", "▏", "▎", "▍", "▌", "▋", "▊", "▉" }

local function bar(pct, width)
  pct = math.max(0, math.min(100, pct or 0))
  width = width or 20
  local units = math.floor(pct / 100 * width * 8 + 0.5)
  local full = math.floor(units / 8)
  local part = units % 8
  local out = string.rep("█", full)
  if full < width then
    out = out .. PARTIAL[part + 1] .. string.rep("░", width - full - 1)
  end
  return out
end

local function num(n)
  local s = tostring(math.floor(n or 0))
  local t = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
  if t:sub(-1) == "," then
    t = t:sub(1, -2)
  end
  return t
end

local function footer(text)
  return { text = "  " .. text, hl = "StorytellerMuted" }
end

local function heat_hl(delta)
  if not delta or delta <= 0 then
    return "StorytellerHeat0"
  end
  if delta < 250 then
    return "StorytellerHeat1"
  end
  if delta < 750 then
    return "StorytellerHeat2"
  end
  if delta < 1500 then
    return "StorytellerHeat3"
  end
  return "StorytellerHeat4"
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

-- Resolve a select entry at the cursor. Entries may be plain data or a
-- function(col) for side-by-side panel layouts.
local function at_cursor(select)
  local line, col = vim.api.nvim_win_get_cursor(0)
  local data = select and select[line]
  if type(data) == "function" then
    -- Cursor columns are byte offsets, while panel bounds are display columns.
    -- Convert before hit-testing cards containing Unicode borders/separators.
    local text = vim.api.nvim_get_current_line()
    return data(vim.fn.strdisplaywidth(text:sub(1, col)))
  end
  return data
end

-- --- Shared Triforce-style builders -----------------------------------------

-- Header block: title, project subtitle, key metrics, and the manuscript
-- progress bar.
function M.header(prj, title, subtitle)
  local chapters = index.chapters(prj)
  local scenes = index.scenes(prj)
  local words = track.total_words(prj)
  local target = 0
  for _, ch in ipairs(chapters) do
    target = target + (ch.target or 0)
  end
  local streaks = track.streaks(prj)
  local pct = target > 0 and math.floor(words / target * 100) or 0
  local lines = {}
  lines[#lines + 1] = { text = "  ✦  " .. title, hl = "StorytellerTitle" }
  lines[#lines + 1] = {
    segments = {
      { text = "  " .. vim.fn.fnamemodify(prj.root, ":t"), hl = "StorytellerAccent" },
      { text = "  ·  " .. subtitle, hl = "StorytellerMuted" },
    },
  }
  lines[#lines + 1] = { text = "", hl = nil }
  lines[#lines + 1] = {
    segments = {
      { text = "  ◈ ", hl = "StorytellerMetric" },
      { text = num(words) .. " words", hl = "StorytellerMetric" },
      { text = "     ◌ ", hl = "StorytellerMetric" },
      { text = streaks.current .. " day streak", hl = "StorytellerMetric" },
      { text = "     ◆ ", hl = "StorytellerMetric" },
      { text = #chapters .. " chapters · " .. #scenes .. " scenes", hl = "StorytellerMetric" },
    },
  }
  lines[#lines + 1] = {
    segments = {
      { text = "  " .. bar(pct, 36), hl = "StorytellerBar" },
      {
        text = string.format("  %d%%%s", pct, target > 0 and (" of " .. num(target)) or ""),
        hl = "StorytellerMuted",
      },
    },
  }
  lines[#lines + 1] = { text = "", hl = nil }
  return lines
end

-- Bordered stats grid (Triforce "Stats" table).
function M.stats_table(prj)
  local chapters = index.chapters(prj)
  local scenes = index.scenes(prj)
  local words = track.total_words(prj)
  local target = 0
  for _, ch in ipairs(chapters) do
    target = target + (ch.target or 0)
  end
  local streaks = track.streaks(prj)
  local activity = track.activity_summary(prj)
  local cols = {
    { label = "Chapters", width = 10 },
    { label = "Scenes", width = 8 },
    { label = "Words", width = 12 },
    { label = "Target", width = 12 },
    { label = "Streak", width = 14 },
    { label = "Active days", width = 12 },
  }
  local function row(values, hl)
    local segs = {}
    for i, c in ipairs(cols) do
      segs[#segs + 1] = { text = string.format("%-" .. c.width .. "s", values[i]), hl = hl }
    end
    return { segments = segs }
  end
  return ui.grid_panels({
    {
      title = "PROJECT",
      rows = {
        row({
          "Chapters",
          "Scenes",
          "Words",
          "Target",
          "Streak",
          "Active days",
        }, "StorytellerTableHeader"),
        row({
          tostring(#chapters),
          tostring(#scenes),
          num(words),
          target > 0 and num(target) or "—",
          streaks.current .. " / " .. streaks.longest,
          tostring(activity.active_days),
        }, "StorytellerMetric"),
      },
    },
  })
end

-- GitHub-style contribution heatmap with month and weekday labels.
function M.activity_panel(prj)
  local weeks = require("storyteller.config").get().heatmap_weeks
  local grid = track.week_grid(prj, weeks)
  local dow_names = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" }
  local content_width = 4 + grid.weeks * 2
  local rows = {}

  -- Month label row. Skip a label when it would collide with the previous
  -- one (month names are wider than a single week column).
  local month_segs = { { text = "    ", hl = nil } }
  local pos = 1
  for w = 1, grid.weeks do
    if grid.months[w] then
      local start = (w - 1) * 2 + 1
      if start >= pos then
        if start > pos then
          month_segs[#month_segs + 1] = { text = string.rep(" ", start - pos), hl = nil }
        end
        month_segs[#month_segs + 1] = { text = grid.months[w], hl = "StorytellerTableHeader" }
        pos = start + #grid.months[w]
      end
    end
  end
  rows[#rows + 1] = { segments = month_segs }

  -- Weekday rows.
  for d = 0, 6 do
    local segs = { { text = string.format("%-4s", dow_names[d + 1]), hl = "StorytellerMuted" } }
    for w = 1, grid.weeks do
      local cell = grid.grid[w][d]
      if cell then
        segs[#segs + 1] = { text = "■ ", hl = heat_hl(cell.delta) }
      else
        segs[#segs + 1] = { text = "  ", hl = nil }
      end
    end
    rows[#rows + 1] = { segments = segs }
  end

  -- Legend row, right aligned.
  local legend = "Less ■ ■ ■ ■ More"
  local legend_segs = {
    { text = string.rep(" ", math.max(0, content_width - #legend)), hl = nil },
    { text = "Less ", hl = "StorytellerMuted" },
    { text = "■", hl = "StorytellerHeat1" },
    { text = " ", hl = nil },
    { text = "■", hl = "StorytellerHeat2" },
    { text = " ", hl = nil },
    { text = "■", hl = "StorytellerHeat3" },
    { text = " ", hl = nil },
    { text = "■", hl = "StorytellerHeat4" },
    { text = " More", hl = "StorytellerMuted" },
  }
  rows[#rows + 1] = { segments = legend_segs }

  return ui.grid_panels({ { title = "ACTIVITY", rows = rows } })
end

-- Milestones laid out three across, achievement-style.
function M.milestones_panel(prj)
  local ms = track.milestones(prj)
  local rows = {}
  for i = 1, #ms, 3 do
    local segs = {}
    for j = i, math.min(i + 2, #ms) do
      local m = ms[j]
      segs[#segs + 1] = {
        text = string.format("%-24s", (m.done and "✓ " or "○ ") .. m.name),
        hl = m.done and "StorytellerDone" or "StorytellerOutline",
      }
    end
    rows[#rows + 1] = { segments = segs }
  end
  return ui.grid_panels({ { title = "MILESTONES", rows = rows } })
end

-- --- Outline ----------------------------------------------------------------

function M.outline(prj)
  prj = prj or project.current()
  ui.view({
    name = "outline",
    prj = prj,
    build = function()
      local lines = {}
      local select = {}
      for _, l in ipairs(M.header(prj, "OUTLINE", "chapter by chapter")) do
        lines[#lines + 1] = l
      end
      local chapters = index.chapters(prj)
      local rows = {}
      for _, ch in ipairs(chapters) do
        local words = index.chapter_words(ch)
        local target = ch.target or 0
        local pct = target > 0 and math.floor(words / target * 100) or 0
        rows[#rows + 1] = {
          segments = {
            { text = string.format("%-26s", ch.title or ch.filename), hl = "StorytellerScene" },
            { text = string.format("%6d w  ", words), hl = "StorytellerMuted" },
            { text = bar(pct, 20), hl = "StorytellerBar" },
            {
              text = string.format(" %3d%%%s", pct, target > 0 and string.format("  %s/%s", num(words), num(target)) or ""),
              hl = "StorytellerMuted",
            },
          },
        }
      end
      local panel = ui.grid_panels({ { title = "CHAPTERS", rows = rows } })
      local offset = #lines
      for _, l in ipairs(panel) do
        lines[#lines + 1] = l
      end
      for i, ch in ipairs(chapters) do
        select[offset + 1 + i] = ch
      end
      lines[#lines + 1] = { text = "", hl = nil }
      lines[#lines + 1] = footer("<CR> open   a status   R refresh   q close")
      return { lines = lines, select = select }
    end,
    on_select = function(ch)
      edit(ch.path)
    end,
    keys = { a = function()
      local sel = vim.b[vim.api.nvim_get_current_buf()].storyteller_select
      local data = at_cursor(sel)
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

local CARD_WIDTH = 34
local CARD_OUTER_WIDTH = CARD_WIDTH + 4

-- Truncate to `width` characters and right-pad with spaces so that every card
-- row lines up regardless of multibyte glyphs.
local function fit(text, width)
  text = tostring(text or "")
  local cl = vim.fn.strchars(text)
  if cl > width then
    return vim.fn.strcharpart(text, 0, width - 1) .. "…"
  end
  return text .. string.rep(" ", width - cl)
end

local function card_row(text, hl)
  return {
    segments = {
      { text = "│ ", hl = "StorytellerCardBorder" },
      { text = fit(text, CARD_WIDTH), hl = hl or "StorytellerScene" },
      { text = " │", hl = "StorytellerCardBorder" },
    },
  }
end

local function scene_card(scene, number)
  local info = meta.scene(scene)
  local m = info.meta
  local status = m.status or "outline"
  local status_hl = ui.status_hl(status) or "StorytellerScene"
  local ch_title = scene.chapter
    and (scene.chapter.title or vim.fn.fnamemodify(scene.path, ":t:r"))
    or "?"
  local label = string.format("SCENE %02d", number or 0)
  local top_prefix = "╭─ " .. label .. " "
  local lines = {}
  lines[#lines + 1] = {
    text = top_prefix
      .. string.rep("─", CARD_OUTER_WIDTH - vim.fn.strdisplaywidth(top_prefix) - 1)
      .. "╮",
    hl = "StorytellerCardBorder",
  }
  lines[#lines + 1] = card_row(scene.title or "Untitled", "StorytellerCardTitle")
  lines[#lines + 1] = card_row(
    string.format("%s · %s", ch_title, status:upper()),
    status_hl
  )
  lines[#lines + 1] = card_row(
    string.format("%s · %s", m.pov or "—", m.location or "—"),
    "StorytellerCardMeta"
  )
  lines[#lines + 1] = card_row(m.beat or m.goal or "No beat recorded.")
  lines[#lines + 1] = card_row(
    string.format("%d words%s", scene.words or 0, m.target and (" · target " .. tostring(m.target)) or ""),
    "StorytellerMetric"
  )
  lines[#lines + 1] = {
    text = "╰" .. string.rep("─", CARD_WIDTH + 2) .. "╯",
    hl = "StorytellerCardBorder",
  }
  return lines
end

function M.corkboard(prj, filter)
  prj = prj or project.current()
  ui.view({
    name = "corkboard",
    prj = prj,
    build = function()
      local lf = filter and filter:lower() or ""
      local scenes = {}
      for _, sc in ipairs(index.scenes(prj)) do
        local info = meta.scene(sc)
        local m = info.meta
        local label = string.format("%s %s %s %s",
          sc.title or "",
          m.pov or "",
          m.location or "",
          sc.chapter and (sc.chapter.title or "") or "")
        if lf == "" or label:lower():find(lf, 1, true) then
          scenes[#scenes + 1] = sc
        end
      end
      -- Keep the board compact: unlike tracking, its content is the cards.
      local lines = {
        { text = "  ✦  CORKBOARD", hl = "StorytellerTitle" },
        {
          segments = {
            { text = "  " .. vim.fn.fnamemodify(prj.root, ":t"), hl = "StorytellerAccent" },
            { text = "  ·  the shape of the story", hl = "StorytellerMuted" },
          },
        },
        { text = "  " .. #scenes .. " scene cards", hl = "StorytellerMuted" },
      }
      local select = {}
      local two_col = vim.o.columns >= CARD_OUTER_WIDTH * 2 + 1
      local columns = two_col and { {}, {} } or { {} }
      local column_scenes = two_col and { {}, {} } or { {} }
      for i, sc in ipairs(scenes) do
        local c = two_col and ((i - 1) % 2) + 1 or 1
        for _, line in ipairs(scene_card(sc, i)) do
          columns[c][#columns[c] + 1] = line
          column_scenes[c][#column_scenes[c] + 1] = sc
        end
        columns[c][#columns[c] + 1] = { text = "" }
        -- `false` preserves the row in the Lua array. A nil value would be
        -- discarded by the length operator and shift later card mappings.
        column_scenes[c][#column_scenes[c] + 1] = false
      end
      local merged, bounds = ui.compose_columns(columns, 1)
      local offset = #lines
      for _, line in ipairs(merged) do
        lines[#lines + 1] = line
      end
      for r = 1, #merged do
        select[offset + r] = function(col)
          if two_col then
            if col + 1 < bounds[2].start then
              return column_scenes[1][r]
            end
            return column_scenes[2][r]
          end
          return column_scenes[1][r]
        end
      end
      lines[#lines + 1] = { text = "", hl = nil }
      lines[#lines + 1] = footer("<CR> open   a status   u unused   R refresh   q close")
      return { lines = lines, select = select }
    end,
    on_select = function(data)
      local sc = type(data) == "function" and at_cursor(vim.b[vim.api.nvim_get_current_buf()].storyteller_select) or data
      if sc then
        index.open_scene(sc)
      end
    end,
    keys = {
      a = function()
        local sel = vim.b[vim.api.nvim_get_current_buf()].storyteller_select
        local sc = at_cursor(sel)
        if sc then
          cycle_status(sc)
        end
      end,
      u = function()
        local sel = vim.b[vim.api.nvim_get_current_buf()].storyteller_select
        local sc = at_cursor(sel)
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

-- --- Timeline ---------------------------------------------------------------

function M.timeline(prj)
  prj = prj or project.current()
  ui.view({
    name = "timeline",
    prj = prj,
    build = function()
      local lines = {}
      local select = {}
      for _, l in ipairs(M.header(prj, "TIMELINE", "story time")) do
        lines[#lines + 1] = l
      end
      local scenes = index.timeline(prj)
      local rows = {}
      for _, scene in ipairs(scenes) do
        local value = scene.timeline_value and tostring(scene.timeline_value) or "unplaced"
        local regression = scene.timeline_regression
        local segs = {}
        segs[#segs + 1] = { text = (regression and "! " or "◆ "), hl = regression and "StorytellerRevision" or "StorytellerAccent" }
        segs[#segs + 1] = { text = string.format("%-10s", value), hl = "StorytellerTableHeader" }
        segs[#segs + 1] = { text = string.format("%-28s", scene.title or "Untitled"), hl = regression and "StorytellerRevision" or "StorytellerScene" }
        segs[#segs + 1] = { text = string.format("%-14s", scene.meta and (scene.meta.pov or "") or ""), hl = "StorytellerCardMeta" }
        if regression then
          segs[#segs + 1] = { text = "moves backward", hl = "StorytellerRevision" }
        end
        rows[#rows + 1] = { segments = segs }
      end
      local panel = ui.grid_panels({ { title = "STORY ORDER", rows = rows } })
      local offset = #lines
      for _, l in ipairs(panel) do
        lines[#lines + 1] = l
      end
      for i, scene in ipairs(scenes) do
        select[offset + 1 + i] = scene
      end
      lines[#lines + 1] = { text = "", hl = nil }
      lines[#lines + 1] = footer("numeric days are ordered · free-form time keeps manuscript order · <CR> open   R refresh   q close")
      return { lines = lines, select = select }
    end,
    on_select = function(scene)
      index.open_scene(scene)
    end,
  })
end

-- --- Plot threads -----------------------------------------------------------

function M.threads(prj)
  prj = prj or project.current()
  ui.view({
    name = "threads",
    prj = prj,
    build = function()
      local lines = {}
      local select = {}
      for _, l in ipairs(M.header(prj, "PLOT THREADS", "setup → payoff")) do
        lines[#lines + 1] = l
      end
      local threads = index.plot_threads(prj)
      local rows = {}
      local row_scenes = {}
      for _, thread in ipairs(threads) do
        local first = thread.setup[1] or thread.payoff[1]
        local done = thread.state == "complete"
        rows[#rows + 1] = {
          segments = {
            { text = (done and "✓ " or "○ "), hl = done and "StorytellerDone" or "StorytellerRevision" },
            { text = string.format("%-24s", thread.key), hl = "StorytellerScene" },
            { text = string.format("%-14s", thread.state), hl = done and "StorytellerDone" or "StorytellerRevision" },
            { text = first and (first.title or "scene") or "—", hl = "StorytellerCardMeta" },
          },
        }
        row_scenes[#row_scenes + 1] = first
      end
      if #threads == 0 then
        rows[#rows + 1] = { text = "No setup or payoff fields yet.", hl = "StorytellerMuted" }
      end
      local panel = ui.grid_panels({ { title = "SETUP → PAYOFF", rows = rows } })
      local offset = #lines
      for _, l in ipairs(panel) do
        lines[#lines + 1] = l
      end
      for i, scene in ipairs(row_scenes) do
        if scene then
          select[offset + 1 + i] = scene
        end
      end
      lines[#lines + 1] = { text = "", hl = nil }
      lines[#lines + 1] = footer("<CR> open scene   R refresh   q close")
      return { lines = lines, select = select }
    end,
    on_select = function(scene)
      index.open_scene(scene)
    end,
  })
end

-- --- Story health -----------------------------------------------------------

function M.health(prj)
  prj = prj or project.current()
  ui.view({
    name = "health",
    prj = prj,
    build = function()
      local lines = {}
      local select = {}
      for _, l in ipairs(M.header(prj, "STORY HEALTH", "loose ends")) do
        lines[#lines + 1] = l
      end
      local findings = index.story_health(prj)
      local rows = {}
      local row_scenes = {}
      if #findings == 0 then
        rows[#rows + 1] = { text = "✓  Everything looks tidy.", hl = "StorytellerDone" }
      else
        for _, finding in ipairs(findings) do
          local scene = finding.scene
          rows[#rows + 1] = {
            segments = {
              { text = "○ ", hl = "StorytellerRevision" },
              { text = string.format("%-24s", finding.label), hl = "StorytellerRevision" },
              { text = scene and (scene.title or "scene") or (finding.thread and finding.thread.key or ""), hl = "StorytellerCardMeta" },
            },
          }
          row_scenes[#row_scenes + 1] = scene
        end
      end
      local panel = ui.grid_panels({ { title = "NEEDS ATTENTION", rows = rows } })
      local offset = #lines
      for _, l in ipairs(panel) do
        lines[#lines + 1] = l
      end
      for i, scene in ipairs(row_scenes) do
        if scene then
          select[offset + 1 + i] = scene
        end
      end
      lines[#lines + 1] = { text = "", hl = nil }
      lines[#lines + 1] = footer("gentle prompts, not blockers · <CR> inspect   R refresh   q close")
      return { lines = lines, select = select }
    end,
    on_select = function(scene)
      index.open_scene(scene)
    end,
  })
end

-- --- Tracking dashboard -----------------------------------------------------

function M.track(prj)
  prj = prj or project.current()
  ui.view({
    name = "track",
    prj = prj,
    build = function()
      local lines = {}
      local select = {}
      for _, l in ipairs(M.header(prj, "TRACKING", "your writing rhythm")) do
        lines[#lines + 1] = l
      end
      for _, l in ipairs(M.stats_table(prj)) do
        lines[#lines + 1] = l
      end
      lines[#lines + 1] = { text = "", hl = nil }
      for _, l in ipairs(M.activity_panel(prj)) do
        lines[#lines + 1] = l
      end
      lines[#lines + 1] = { text = "", hl = nil }

      -- Chapter progress.
      local chapters = index.chapters(prj)
      local sum = 0
      local chapter_rows = {}
      for _, ch in ipairs(chapters) do
        local words = index.chapter_words(ch)
        local target = ch.target or 0
        sum = sum + target
        local pct = target > 0 and math.floor(words / target * 100) or 0
        chapter_rows[#chapter_rows + 1] = {
          segments = {
            { text = string.format("%-24s", ch.title or ch.filename), hl = "StorytellerScene" },
            { text = string.format("%6d w  ", words), hl = "StorytellerMuted" },
            { text = bar(pct, 20), hl = "StorytellerBar" },
            {
              text = string.format(" %3d%%%s", pct, target > 0 and string.format("  %s/%s", num(words), num(target)) or ""),
              hl = "StorytellerMuted",
            },
          },
        }
      end
      if sum > 0 then
        local total = track.total_words(prj)
        local pct = math.floor(total / sum * 100)
        chapter_rows[#chapter_rows + 1] = {
          segments = {
            { text = string.rep(" ", 24), hl = nil },
            { text = string.format("%6s  ", "manuscript"), hl = "StorytellerTableHeader" },
            { text = bar(pct, 20), hl = "StorytellerBar" },
            { text = string.format(" %3d%%  %s/%s", pct, num(total), num(sum)), hl = "StorytellerMetric" },
          },
        }
      end
      local cp = ui.grid_panels({ { title = "CHAPTER PROGRESS", rows = chapter_rows } })
      local cp_offset = #lines
      for _, l in ipairs(cp) do
        lines[#lines + 1] = l
      end
      for i, ch in ipairs(chapters) do
        select[cp_offset + 1 + i] = ch
      end
      lines[#lines + 1] = { text = "", hl = nil }

      local s = track.session_stats()
      if s then
        lines[#lines + 1] = {
          segments = {
            { text = "  ◷ ", hl = "StorytellerMetric" },
            { text = string.format("session +%d words since %s", s.written, s.started_at), hl = "StorytellerMetric" },
          },
        }
        lines[#lines + 1] = { text = "", hl = nil }
      end

      for _, l in ipairs(M.milestones_panel(prj)) do
        lines[#lines + 1] = l
      end

      local balance = track.pov_balance(prj)
      if #balance.pov_order > 0 then
        lines[#lines + 1] = { text = "", hl = nil }
        local pov_rows = {}
        for _, pov in ipairs(balance.pov_order) do
          local n = balance.povs[pov]
          local pct = balance.total_scenes > 0 and math.floor(n / balance.total_scenes * 100) or 0
          pov_rows[#pov_rows + 1] = {
            segments = {
              { text = string.format("%-24s", pov), hl = "StorytellerScene" },
              { text = string.format("%3d scenes  ", n), hl = "StorytellerMuted" },
              { text = bar(pct, 20), hl = "StorytellerBar" },
              { text = string.format(" %3d%%", pct), hl = "StorytellerMuted" },
            },
          }
        end
        for _, l in ipairs(ui.grid_panels({ { title = "POV BALANCE", rows = pov_rows } })) do
          lines[#lines + 1] = l
        end
      end

      lines[#lines + 1] = { text = "", hl = nil }
      lines[#lines + 1] = footer("<CR> chapter   s session   p progress   R refresh   q close")
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
      local lines = {}
      local select = {}
      lines[#lines + 1] = { text = "  ✦  BINDER", hl = "StorytellerTitle" }
      lines[#lines + 1] = { text = "", hl = nil }
      local chapters = index.chapters(prj)
      local rows = {}
      local row_data = {}
      for _, ch in ipairs(chapters) do
        rows[#rows + 1] = { text = "▸  " .. (ch.title or ch.filename), hl = "StorytellerSection" }
        row_data[#row_data + 1] = ch
        for _, sc in ipairs(ch.scenes) do
          local status = scene_status(sc)
          rows[#rows + 1] = {
            segments = {
              { text = "   ·  ", hl = "StorytellerDivider" },
              { text = sc.title or "(untitled)", hl = ui.status_hl(status) or "StorytellerScene" },
            },
          }
          row_data[#row_data + 1] = sc
        end
      end
      local panel = ui.grid_panels({ { title = "CHAPTERS / SCENES", rows = rows } })
      local offset = #lines
      for _, l in ipairs(panel) do
        lines[#lines + 1] = l
      end
      for i, data in ipairs(row_data) do
        select[offset + 1 + i] = data
      end
      lines[#lines + 1] = { text = "", hl = nil }
      lines[#lines + 1] = footer("<CR> open   R refresh   q close")
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
      local lines = {}
      lines[#lines + 1] = { text = "  ✦  " .. (scene.title or "SCENE"):upper(), hl = "StorytellerTitle" }
      lines[#lines + 1] = { text = "", hl = nil }
      local status_hl = ui.status_hl(m.status or "outline") or "StorytellerScene"
      local context = ui.grid_panels({
        {
          title = "CONTEXT",
          rows = {
            {
              segments = {
                { text = "Status   ", hl = "StorytellerTableHeader" },
                { text = m.status or "outline", hl = status_hl },
              },
            },
            {
              segments = {
                { text = "POV      ", hl = "StorytellerTableHeader" },
                { text = m.pov or "—", hl = "StorytellerScene" },
              },
            },
            {
              segments = {
                { text = "Location ", hl = "StorytellerTableHeader" },
                { text = m.location or "—", hl = "StorytellerScene" },
              },
            },
            {
              segments = {
                { text = "Time     ", hl = "StorytellerTableHeader" },
                { text = tostring(m.time or m.day or "—"), hl = "StorytellerMuted" },
              },
            },
          },
        },
        {
          title = "BEAT",
          rows = {
            { text = tostring(m.beat or "No beat recorded."), hl = "StorytellerScene" },
          },
        },
      })
      for _, l in ipairs(context) do
        lines[#lines + 1] = l
      end
      lines[#lines + 1] = { text = "", hl = nil }
      local beat = ui.grid_panels({
        {
          title = "GOAL / CONFLICT / OUTCOME",
          rows = {
            {
              segments = {
                { text = "Goal      ", hl = "StorytellerTableHeader" },
                { text = tostring(m.goal or "—"), hl = "StorytellerScene" },
              },
            },
            {
              segments = {
                { text = "Conflict  ", hl = "StorytellerTableHeader" },
                { text = tostring(m.conflict or "—"), hl = "StorytellerScene" },
              },
            },
            {
              segments = {
                { text = "Outcome   ", hl = "StorytellerTableHeader" },
                { text = tostring(m.outcome or "—"), hl = "StorytellerScene" },
              },
            },
          },
        },
      })
      for _, l in ipairs(beat) do
        lines[#lines + 1] = l
      end
      lines[#lines + 1] = { text = "", hl = nil }
      lines[#lines + 1] = footer("m edit meta   R refresh   q close")
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
      local lines = {}
      lines[#lines + 1] = { text = "  ✦  TEMPLATE  " .. (plan.template.name or plan.template.id), hl = "StorytellerTitle" }
      lines[#lines + 1] = { text = "  " .. #plan.created .. " chapter(s) to create · " .. #plan.skipped .. " skipped", hl = "StorytellerMetric" }
      lines[#lines + 1] = { text = "", hl = nil }
      local rows = {}
      for _, p in ipairs(plan.created) do
        rows[#rows + 1] = { text = "+ " .. vim.fn.fnamemodify(p, ":t"), hl = "StorytellerDone" }
      end
      for _, p in ipairs(plan.skipped) do
        rows[#rows + 1] = { text = "= " .. vim.fn.fnamemodify(p, ":t") .. "  (exists)", hl = "StorytellerMuted" }
      end
      for _, l in ipairs(ui.grid_panels({ { title = "PREVIEW", rows = rows } })) do
        lines[#lines + 1] = l
      end
      lines[#lines + 1] = { text = "", hl = nil }
      lines[#lines + 1] = footer("a apply   q cancel")
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
