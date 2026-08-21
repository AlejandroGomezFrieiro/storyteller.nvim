-- storyteller.ui
-- The UI layer: a single highlight palette and a reusable view renderer used
-- by every read-only screen. Editable surfaces live in ui/storyboard.lua.

local M = {}

-- --- Highlight palette (single home for all view colours) --------------------

local palette_done = false

function M.palette()
  if palette_done then
    return
  end
  palette_done = true

  vim.api.nvim_set_hl(0, "StorytellerTitle", { default = true, fg = "#f2d5cf", bold = true })
  vim.api.nvim_set_hl(0, "StorytellerAccent", { default = true, fg = "#8caaee", bold = true })
  vim.api.nvim_set_hl(0, "StorytellerSection", { default = true, fg = "#ca9ee6", bold = true })
  vim.api.nvim_set_hl(0, "StorytellerScene", { default = true, fg = "#c6d0f5" })
  vim.api.nvim_set_hl(0, "StorytellerMuted", { default = true, fg = "#949cbb", italic = true })
  vim.api.nvim_set_hl(0, "StorytellerMetric", { default = true, fg = "#a6d189", bold = true })
  vim.api.nvim_set_hl(0, "StorytellerKey", { default = true, fg = "#f4b8e4", bold = true })
  vim.api.nvim_set_hl(0, "StorytellerDivider", { default = true, fg = "#626880" })
  vim.api.nvim_set_hl(0, "StorytellerBar", { default = true, fg = "#8caaee" })
  vim.api.nvim_set_hl(0, "StorytellerOutline", { default = true, fg = "#949cbb" })
  vim.api.nvim_set_hl(0, "StorytellerDraft", { default = true, fg = "#f4b8e4" })
  vim.api.nvim_set_hl(0, "StorytellerRevision", { default = true, fg = "#e5c890" })
  vim.api.nvim_set_hl(0, "StorytellerDone", { default = true, fg = "#a6d189" })
  vim.api.nvim_set_hl(0, "StorytellerUnused", { default = true, fg = "#e78284" })
  vim.api.nvim_set_hl(0, "StorytellerCardBorder", { default = true, fg = "#626880" })
  vim.api.nvim_set_hl(0, "StorytellerCardTitle", { default = true, fg = "#f2d5cf", bold = true })
  vim.api.nvim_set_hl(0, "StorytellerCardMeta", { default = true, fg = "#b5bfe2" })
  vim.api.nvim_set_hl(0, "StorytellerPanelTitle", { default = true, fg = "#8caaee", bold = true })
  vim.api.nvim_set_hl(0, "StorytellerTableHeader", { default = true, fg = "#949cbb", bold = true })
  -- Semantic slots mirroring tui/src/theme.rs (docs/tui-visual-plan.md §4):
  -- Surface = card/panel background tint, Selection = focused row.
  vim.api.nvim_set_hl(0, "StorytellerSurface", { default = true, bg = "#363b4e" })
  vim.api.nvim_set_hl(0, "StorytellerSelection", { default = true, bg = "#414559" })
  vim.api.nvim_set_hl(0, "StorytellerHeat0", { default = true, fg = "#414559" })
  vim.api.nvim_set_hl(0, "StorytellerHeat1", { default = true, fg = "#737aa2" })
  vim.api.nvim_set_hl(0, "StorytellerHeat2", { default = true, fg = "#8caaee" })
  vim.api.nvim_set_hl(0, "StorytellerHeat3", { default = true, fg = "#ca9ee6" })
  vim.api.nvim_set_hl(0, "StorytellerHeat4", { default = true, fg = "#f4b8e4" })

  -- Composition mode: dimmed backdrop, calm writing surface.
  local ok_bg, normal = pcall(vim.api.nvim_get_hl, 0, { name = "Normal", link = false })
  local bg = (ok_bg and normal and normal.bg) or nil
  vim.api.nvim_set_hl(0, "StorytellerComposeBackdrop", {
    default = true,
    fg = 0x000000,
    bg = bg and M.darken(bg, 0.55) or "#1a1b26",
  })
  vim.api.nvim_set_hl(0, "StorytellerCompose", { default = true })
end

-- Blend a color toward black by `amount` (0..1). Keeps composition mode's
-- backdrop theme-aware.
function M.darken(rgb, amount)
  amount = math.max(0, math.min(1, amount or 0.5))
  local r = math.floor((rgb % 256) * (1 - amount))
  local g = math.floor((math.floor(rgb / 256) % 256) * (1 - amount))
  local b = math.floor(math.floor(rgb / 65536) * (1 - amount))
  return r + g * 256 + b * 65536
end

function M.status_hl(status)
  local map = {
    outline = "StorytellerOutline",
    draft = "StorytellerDraft",
    revision = "StorytellerRevision",
    done = "StorytellerDone",
    unused = "StorytellerUnused",
  }
  return map[status]
end

-- --- Generic view renderer --------------------------------------------------

local buffers = {}

local function key(name, root)
  return name .. "\0" .. root
end

-- Render `lines` (array of { text, hl? } or plain strings) into a nofile
-- buffer, with a `select` map of display-line-number -> data.
function M.render_view(buf, lines, select)
  M.palette()
  M.buffer_render(buf, lines)
  vim.b[buf].storyteller_select = select or {}
  return select
end

-- Normalize one render line into a list of { text, hl? } runs. A line may be a
-- plain string, a single `{ text, hl }`, or `{ segments = { {text, hl}, ... } }`.
local function runs(item)
  if type(item) == "table" and type(item.segments) == "table" then
    local out = {}
    for _, seg in ipairs(item.segments) do
      if type(seg) == "table" then
        out[#out + 1] = { text = seg.text or "", hl = seg.hl }
      else
        out[#out + 1] = { text = seg, hl = nil }
      end
    end
    return out
  end
  if type(item) == "table" then
    return { { text = item.text or "", hl = item.hl } }
  end
  return { { text = item, hl = nil } }
end

local function line_width(item)
  local width = 0
  for _, run in ipairs(runs(item)) do
    width = width + vim.fn.strdisplaywidth(run.text)
  end
  return width
end

-- Compose side-by-side columns of line items (Triforce-style panels).
-- `columns` is a list of vertical line lists; shorter columns are padded with
-- blank lines. Returns the merged `lines` and `bounds`, where bounds[i] gives
-- the display-column start and width of column i (for hit-testing the cursor).
function M.compose_columns(columns, gap)
  gap = gap or 1
  local max_rows = 0
  for _, col in ipairs(columns) do
    if #col > max_rows then
      max_rows = #col
    end
  end
  local widths = {}
  for i, col in ipairs(columns) do
    local w = 0
    for _, item in ipairs(col) do
      local lw = line_width(item)
      if lw > w then
        w = lw
      end
    end
    widths[i] = w
  end
  local lines = {}
  for r = 1, max_rows do
    local segs = {}
    for i, col in ipairs(columns) do
      if i > 1 then
        segs[#segs + 1] = { text = string.rep(" ", gap) }
      end
      local item = col[r]
      if item then
        for _, run in ipairs(runs(item)) do
          segs[#segs + 1] = run
        end
        local lw = line_width(item)
        if lw < widths[i] then
          segs[#segs + 1] = { text = string.rep(" ", widths[i] - lw) }
        end
      else
        segs[#segs + 1] = { text = string.rep(" ", widths[i]) }
      end
    end
    lines[#lines + 1] = { segments = segs }
  end
  local bounds = {}
  local col = 1
  for i, _ in ipairs(columns) do
    if i > 1 then
      col = col + gap
    end
    bounds[i] = { start = col, width = widths[i] }
    col = col + widths[i]
  end
  return lines, bounds
end

-- Build bordered panels side by side. Each panel is { title, rows }, where
-- title is a string or { segments = {...} } and rows are line items.
function M.grid_panels(panels)
  local columns = {}
  for i, panel in ipairs(panels) do
    local col = {}
    local title_len
    if type(panel.title) == "table" then
      title_len = line_width(panel.title)
    else
      title_len = #tostring(panel.title or "")
    end
    local width = title_len
    for _, row in ipairs(panel.rows) do
      local lw = line_width(row)
      if lw > width then
        width = lw
      end
    end
    -- Top border.
    local top = {
      { text = "╭─ ", hl = "StorytellerDivider" },
    }
    if type(panel.title) == "table" then
      for _, seg in ipairs(panel.title.segments) do
        top[#top + 1] = seg
      end
    else
      top[#top + 1] = { text = tostring(panel.title or ""), hl = "StorytellerPanelTitle" }
    end
    top[#top + 1] = {
      text = string.rep("─", math.max(1, width - title_len)) .. "╮",
      hl = "StorytellerDivider",
    }
    col[#col + 1] = { segments = top }
    -- Body rows, padded to a common width.
    for _, row in ipairs(panel.rows) do
      local segs = { { text = "│ ", hl = "StorytellerDivider" } }
      for _, run in ipairs(runs(row)) do
        segs[#segs + 1] = run
      end
      local lw = line_width(row)
      if lw < width then
        segs[#segs + 1] = { text = string.rep(" ", width - lw) }
      end
      segs[#segs + 1] = { text = " │", hl = "StorytellerDivider" }
      col[#col + 1] = { segments = segs }
    end
    -- Bottom border.
    col[#col + 1] =
      { text = "╰" .. string.rep("─", width + 2) .. "╯", hl = "StorytellerDivider" }
    columns[i] = col
  end
  return M.compose_columns(columns, 1)
end

-- Plain buffer renderer (always available).
function M.buffer_render(buf, lines)
  vim.bo[buf].modifiable = true
  local text = {}
  local flat = {}
  for _, item in ipairs(lines) do
    local line = {}
    for _, run in ipairs(runs(item)) do
      line[#line + 1] = run.text
    end
    text[#text + 1] = table.concat(line)
    flat[#flat + 1] = runs(item)
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, text)

  local ns = vim.api.nvim_create_namespace("storyteller.ui")
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for i, line_runs in ipairs(flat) do
    local col = 0
    for _, run in ipairs(line_runs) do
      if run.hl then
        vim.api.nvim_buf_add_highlight(buf, ns, run.hl, i - 1, col, col + #run.text)
      end
      col = col + #run.text
    end
  end
  vim.bo[buf].modifiable = false
end

-- Open (or reuse) a view. opts = {
--   name, prj, title,
--   build()  -> { lines = {...}, select = {...}, winbar? },
--   on_select(data, line),
--   keys = { [lhs] = fn }  -- extra buffer-local keymaps
-- }
function M.view(opts)
  local prj = opts.prj or require("storyteller.project").current()
  if not prj then
    vim.notify("[storyteller] Not in a storytelling project.", vim.log.levels.WARN)
    return nil
  end
  local id = key(opts.name, prj.root)
  local buf = buffers[id]
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then
    buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(
      buf,
      "storyteller://" .. opts.name .. "/" .. vim.fn.fnamemodify(prj.root, ":t")
    )
    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].swapfile = false
    vim.bo[buf].filetype = "storyteller-" .. opts.name
    vim.b[buf].storyteller_project = prj
    buffers[id] = buf
    vim.api.nvim_create_autocmd("BufWipeout", {
      buffer = buf,
      once = true,
      callback = function()
        buffers[id] = nil
      end,
    })
  end

  local function refresh()
    local built = opts.build and opts.build() or { lines = {} }
    M.render_view(buf, built.lines, built.select)
    vim.b[buf].storyteller_refresh = refresh
    if built.winbar then
      vim.wo.winbar = built.winbar
    end
  end
  refresh()

  vim.wo.number = false
  vim.wo.relativenumber = false
  vim.wo.signcolumn = "no"
  vim.wo.foldcolumn = "0"
  vim.wo.cursorline = true
  vim.wo.wrap = false
  vim.wo.spell = false

  vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf, silent = true, desc = "Close" })
  vim.keymap.set("n", "R", function()
    local fn = vim.b[buf].storyteller_refresh
    if fn then
      fn()
    end
  end, { buffer = buf, silent = true, desc = "Refresh" })
  if opts.on_select then
    vim.keymap.set("n", "<CR>", function()
      local sel = vim.b[buf].storyteller_select
      local data = sel[vim.api.nvim_win_get_cursor(0)[1]]
      if data then
        opts.on_select(data, vim.api.nvim_win_get_cursor(0)[1])
      end
    end, { buffer = buf, silent = true, desc = "Open" })
  end
  if opts.keys then
    for lhs, fn in pairs(opts.keys) do
      vim.keymap.set("n", lhs, fn, { buffer = buf, silent = true })
    end
  end

  vim.api.nvim_set_current_buf(buf)
  return buf
end

-- --- Heatmap ----------------------------------------------------------------

function M.heatmap_lines(deltas)
  local levels = { " ", "░", "▒", "▓", "█" }
  local function glyph(delta)
    if not delta or delta <= 0 then
      return levels[1]
    elseif delta < 250 then
      return levels[2]
    elseif delta < 750 then
      return levels[3]
    elseif delta < 1500 then
      return levels[4]
    end
    return levels[5]
  end
  local cols = 7
  local lines = {}
  for i = 1, #deltas, cols do
    local row = {}
    for c = 0, cols - 1 do
      local e = deltas[i + c]
      row[#row + 1] = glyph(e and e.delta or 0)
    end
    lines[#lines + 1] = table.concat(row, " ")
  end
  return lines
end

function M.heatmap_segments(deltas)
  local function level(delta)
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
  local rows = {}
  for i = 1, #deltas, 7 do
    local segments = {}
    for c = 0, 6 do
      local entry = deltas[i + c]
      segments[#segments + 1] = { text = "▣ ", hl = level(entry and entry.delta or 0) }
    end
    rows[#rows + 1] = { segments = segments }
  end
  return rows
end

return M
