-- storyteller.ui.board_hl
-- Extmark styling for storyboard buffers. The buffer text stays canonical and
-- fully editable (docs/projections.md); every bit of presentation here is an
-- overlay in one namespace, cleared and repainted from the current lines.
--
-- Palette mapping (mirrors tui/src/theme.rs slots, docs/tui-visual-plan.md §4):
--   banner        -> StorytellerTitle        card header  -> CardTitle + Surface band
--   field keys    -> StorytellerKey          status value -> status group
--   file: address -> StorytellerMuted        words:       -> StorytellerMetric
--   table header  -> StorytellerTableHeader  separator    -> StorytellerDivider
--   day cells     -> StorytellerAccent       unscheduled  -> StorytellerMuted

local ui = require("storyteller.ui")

local M = {}

local ns = vim.api.nvim_create_namespace("storyteller-board")

local function hl(buf, row, start_col, end_col, group, opts)
  local payload = {
    end_row = row,
    end_col = end_col,
    hl_group = group,
  }
  if opts then
    for k, v in pairs(opts) do
      payload[k] = v
    end
  end
  vim.api.nvim_buf_set_extmark(buf, ns, row, start_col, payload)
end

-- Whole visible line.
local function line(buf, row, width, group)
  hl(buf, row, 0, width, group)
end

-- Full-width band including the trailing newline.
local function band(buf, row, group)
  hl(buf, row, 0, 0, group, { end_row = row + 1 })
end

-- Highlight `key: value` inside a body line: key in StorytellerKey, the value
-- in `value_group` when given.
local function field(buf, row, ln, value_group)
  local key = ln:match("^(%w+):")
  if not key then
    return
  end
  hl(buf, row, 0, #key + 1, "StorytellerKey")
  if value_group then
    local vstart = #key + 1
    while vstart < #ln and ln:sub(vstart + 1, vstart + 1) == " " do
      vstart = vstart + 1
    end
    if vstart < #ln then
      hl(buf, row, vstart, #ln, value_group)
    end
  end
end

-- --- Corkboard --------------------------------------------------------------

local function paint_corkboard(buf, lines)
  for i, ln in ipairs(lines) do
    local row = i - 1
    if ln:match("^# ") then
      line(buf, row, #ln, "StorytellerTitle")
    elseif ln:match("^## ") then
      band(buf, row, "StorytellerSurface")
      hl(buf, row, 0, #ln, "StorytellerCardTitle")
    elseif ln:match("^file:") then
      line(buf, row, #ln, "StorytellerMuted")
    elseif ln:match("^words:") then
      local key_end = ln:find(":", 1, true) or 0
      hl(buf, row, 0, key_end, "StorytellerMuted")
      hl(buf, row, key_end, #ln, "StorytellerMetric")
    elseif ln:match("^%w+:") then
      local key = ln:match("^(%w+):")
      local value = vim.trim(ln:match("^%w+:%s*(.*)$") or "")
      local value_group
      if key == "status" then
        value_group = ui.status_hl(value) or "StorytellerScene"
      elseif key == "day" then
        value_group = "StorytellerAccent"
      elseif key == "target" then
        value_group = "StorytellerMetric"
      end
      field(buf, row, ln, value_group)
    end
  end
end

-- --- Timeline / metasheet (pipe tables) --------------------------------------

-- Split a table row into { start, end_ } byte ranges per cell.
local function cells(ln)
  local out = {}
  local start = 1
  while true do
    local pipe = ln:find("|", start, true)
    if pipe then
      out[#out + 1] = { start - 1, pipe - 1 }
      start = pipe + 1
    else
      out[#out + 1] = { start - 1, #ln }
      break
    end
  end
  return out
end

local function paint_table(buf, lines, kind)
  local header_seen = false
  for i, ln in ipairs(lines) do
    local row = i - 1
    if ln:match("^# ") then
      line(buf, row, #ln, "StorytellerTitle")
    elseif ln:match("^%-") and ln:find("+", 1, true) then
      line(buf, row, #ln, "StorytellerDivider")
      header_seen = true
    elseif ln:find("|", 1, true) and not header_seen then
      line(buf, row, #ln, "StorytellerTableHeader")
    elseif ln:find("|", 1, true) then
      local ranges = cells(ln)
      for ci, range in ipairs(ranges) do
        local text = vim.trim(ln:sub(range[1] + 1, range[2]))
        local group
        if kind == "timeline" then
          group = (ci == 1 and text ~= "·") and "StorytellerAccent"
            or (ci == 1 and "StorytellerMuted")
            or (ci == 2 and "StorytellerScene")
            or (ci == 3 and "StorytellerMuted")
            or (ci == 4 and "StorytellerMetric")
        else
          group = (ci == 1 and "StorytellerScene")
            or (ci == 2 and (ui.status_hl(text) or "StorytellerScene"))
            or (ci == 4 and "StorytellerMuted")
            or (ci == 5 and "StorytellerAccent")
            or (ci == 6 and "StorytellerMetric")
        end
        if group then
          hl(buf, row, range[1], range[2], group)
        end
      end
    end
  end
end

-- --- Synopsis ----------------------------------------------------------------

local function paint_synopsis(buf, lines)
  for i, ln in ipairs(lines) do
    local row = i - 1
    if ln == "# Synopsis" then
      line(buf, row, #ln, "StorytellerTitle")
    elseif ln:match("^## ") then
      line(buf, row, #ln, "StorytellerScene")
    elseif ln:match("^# ") then
      line(buf, row, #ln, "StorytellerSection")
    end
  end
end

local PAINTERS = {
  corkboard = paint_corkboard,
  timeline = function(buf, lines)
    paint_table(buf, lines, "timeline")
  end,
  metasheet = function(buf, lines)
    paint_table(buf, lines, "metasheet")
  end,
  synopsis = paint_synopsis,
}

-- Restyle a storyboard buffer from its current lines.
function M.paint(buf, name)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  ui.palette()
  local paint = PAINTERS[name]
  if paint then
    paint(buf, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
  end
end

M.namespace = ns

return M
