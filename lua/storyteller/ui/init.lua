-- storyteller.ui
-- The UI layer: a single highlight palette, a backend probe (morph + nui with
-- a plain-buffer fallback), and a reusable view renderer used by every screen.

local M = {}

local config = require("storyteller.config")

-- --- Highlight palette (single home for all view colours) --------------------

local palette_done = false

function M.palette()
  if palette_done then
    return
  end
  palette_done = true

  -- Derive a group from a built-in target, carrying its colour forward while
  -- layering on attributes (bold/italic/underline). Falls back to a plain link
  -- when the target has no resolvable foreground.
  local function style(name, target, opts)
    opts = opts or {}
    local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = target, link = false })
    local def = { default = true }
    if ok and hl and hl.fg then
      def.fg = hl.fg
      if opts.bg and hl.bg then
        def.bg = hl.bg
      end
    else
      def.link = target
    end
    if opts.bold then
      def.bold = true
    end
    if opts.italic then
      def.italic = true
    end
    if opts.underline then
      def.underline = true
    end
    vim.api.nvim_set_hl(0, name, def)
  end

  -- Triforce-inspired: a quiet deep background, jewel accents, and a small
  -- number of emphatic colors so the dashboards feel rewarding, not noisy.
  local direct = {
    StorytellerTitle = { fg = "#f2d5cf", bold = true },
    StorytellerAccent = { fg = "#8caaee", bold = true },
    StorytellerSection = { fg = "#ca9ee6", bold = true },
    StorytellerScene = { fg = "#c6d0f5" },
    StorytellerMuted = { fg = "#949cbb", italic = true },
    StorytellerMetric = { fg = "#a6d189", bold = true },
    StorytellerKey = { fg = "#f4b8e4", bold = true },
    StorytellerDivider = { fg = "#626880" },
    StorytellerBar = { fg = "#8caaee" },
    StorytellerOutline = { fg = "#949cbb" },
    StorytellerDraft = { fg = "#f4b8e4" },
    StorytellerRevision = { fg = "#e5c890" },
    StorytellerDone = { fg = "#a6d189" },
    StorytellerUnused = { fg = "#e78284" },
    StorytellerCardBorder = { fg = "#626880" },
    StorytellerCardTitle = { fg = "#f2d5cf", bold = true },
    StorytellerCardMeta = { fg = "#b5bfe2" },
    StorytellerPanelTitle = { fg = "#8caaee", bold = true },
    StorytellerTableHeader = { fg = "#949cbb", bold = true },
    StorytellerHeat0 = { fg = "#414559" },
    StorytellerHeat1 = { fg = "#737aa2" },
    StorytellerHeat2 = { fg = "#8caaee" },
    StorytellerHeat3 = { fg = "#ca9ee6" },
    StorytellerHeat4 = { fg = "#f4b8e4" },
  }
  for name, def in pairs(direct) do
    vim.api.nvim_set_hl(0, name, vim.tbl_extend("force", { default = true }, def))
  end
end

local function has(mod)
  return pcall(require, mod)
end

function M.has_morph()
  return has("storyteller.morph")
end

function M.has_nui()
  return has("nui.popup") and has("nui.split") and has("nui.layout")
end

function M.backend()
  local cfg = config.get()
  if cfg.ui == "morph" and M.has_morph() then
    return "morph"
  end
  if cfg.ui == "nui" and M.has_nui() then
    return "nui"
  end
  if cfg.ui == "buffer" then
    return "buffer"
  end
  if M.has_morph() then
    return "morph"
  end
  return "buffer"
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
-- buffer, with a `select` map of display-line-number -> data. Uses the morph
-- renderer when available, otherwise a plain highlight path.
function M.render_view(buf, lines, select)
  M.palette()
  if not M.morph_render(buf, lines) then
    M.buffer_render(buf, lines)
  end
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
    local width = 0
    if type(panel.title) == "table" then
      width = line_width(panel.title)
    else
      width = #tostring(panel.title or "")
    end
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
    local title_len = 0
    if type(panel.title) == "table" then
      title_len = line_width(panel.title)
    else
      title_len = #tostring(panel.title or "")
    end
    top[#top + 1] = { text = string.rep("─", math.max(1, width - title_len)) .. "╮", hl = "StorytellerDivider" }
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
    col[#col + 1] = { text = "╰" .. string.rep("─", width + 2) .. "╯", hl = "StorytellerDivider" }
    columns[i] = col
  end
  return M.compose_columns(columns, 1)
end

-- Render via morph.nvim (declarative, reconciled). Returns false to fall back.
local morph_renderers = {}

function M.morph_render(buf, lines)
  if M.backend() ~= "morph" then
    return false
  end
  local ok, morph = pcall(require, "storyteller.morph")
  if not ok then
    return false
  end
  local h = morph.h
  local tree = {}
  for i, item in ipairs(lines) do
    if i > 1 then
      tree[#tree + 1] = "\n"
    end
    for _, run in ipairs(runs(item)) do
      if run.hl then
        tree[#tree + 1] = h("text", { hl = run.hl }, run.text)
      else
        tree[#tree + 1] = run.text
      end
    end
  end
  local renderer = morph_renderers[buf]
  if not renderer then
    local ok2, r = pcall(morph.new, buf)
    if not ok2 then
      return false
    end
    renderer = r
    morph_renderers[buf] = renderer
  end
  vim.bo[buf].modifiable = true
  local ok3 = pcall(function()
    renderer:mount(tree)
  end)
  vim.bo[buf].modifiable = false
  return ok3
end

function M.morph_forget(buf)
  morph_renderers[buf] = nil
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
    vim.api.nvim_buf_set_name(buf, "storyteller://" .. opts.name .. "/" .. vim.fn.fnamemodify(prj.root, ":t"))
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
        M.morph_forget(buf)
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
    if not delta or delta <= 0 then return "StorytellerHeat0" end
    if delta < 250 then return "StorytellerHeat1" end
    if delta < 750 then return "StorytellerHeat2" end
    if delta < 1500 then return "StorytellerHeat3" end
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
