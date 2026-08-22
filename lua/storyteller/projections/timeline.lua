-- storyteller.projections.timeline
-- Story time as an editable table (docs/projections.md): one row per scene
-- ordered by numeric `day:`. Editing the day cell retimes the scene; the row
-- order itself always follows the days, so row moves normalize away.

local index = require("storyteller.index")
local corkboard = require("storyteller.projections.corkboard")

local M = {}

local COLS = { "day", "title", "pov", "words" }

-- Render one axis (default main). Secondary (`also:` placement) rows carry a
-- `*` day-cell suffix: they are visible but not writable here — the scene's
-- YAML holds the placement.
function M.render(prj, axis)
  local entries = index.timeline(prj, axis)
  corkboard.disambiguate(entries)
  local rows = {}
  local widths = { day = 3, title = 5, pov = 3, words = 5 }
  for _, sc in ipairs(entries) do
    local m = sc.meta or {}
    local value
    if sc.timeline_secondary then
      value = tostring(sc.timeline_value or "·")
    else
      value = m.day ~= nil and tostring(m.day) or (m.time and tostring(m.time) or "·")
      if m.day == nil and tonumber(m.time) then
        value = tostring(tonumber(m.time))
      end
    end
    local day = value .. (sc.timeline_secondary and "*" or "")
    local row = {
      day = day,
      title = sc._label or sc.title or "Untitled",
      pov = corkboard.stringify(m.pov or "—"),
      words = tostring(sc.words or 0),
    }
    for _, c in ipairs(COLS) do
      widths[c] = math.max(widths[c], vim.fn.strdisplaywidth(row[c]))
    end
    rows[#rows + 1] = { scene = sc, cells = row }
  end

  local meta_axis = index.timeline_axes(prj)
  local unit = ""
  for _, a in ipairs(meta_axis) do
    if a.name:lower() == (axis or "main"):lower() and a.unit then
      unit = " · " .. a.unit
    end
  end

  local function line(cells, pad_char)
    local out = {}
    for _, c in ipairs(COLS) do
      out[#out + 1] = cells[c] .. string.rep(pad_char or " ", widths[c] - #cells[c])
    end
    return table.concat(out, " | ")
  end

  local lines = {
    "# Timeline · " .. (axis or "main") .. unit,
    "",
    line({ day = "day", title = "title", pov = "pov", words = "words" }),
    table.concat({
      string.rep("-", widths.day),
      string.rep("-", widths.title),
      string.rep("-", widths.pov),
      string.rep("-", widths.words),
    }, "-+-"),
  }

  local records = {}
  for i, row in ipairs(rows) do
    lines[#lines + 1] = line(row.cells)
    records[#records + 1] = {
      title = row.cells.title,
      raw_title = row.scene.title,
      day_cell = row.cells.day,
      secondary = row.scene.timeline_secondary or false,
      fields = { day = row.cells.day, title = row.cells.title },
      lnum = #lines,
      scene = row.scene,
    }
  end
  return { lines = lines, records = records }
end

-- Parse rows back out of edited text. Identity is the (disambiguated) title.
-- A trailing `*` in the day cell marks a secondary (`also:`) placement row;
-- the marker is stripped and remembered.
function M.parse(lines)
  local records = {}
  local header_seen = false
  for _, ln in ipairs(lines) do
    if ln:match("^%-+%-%-") then
      header_seen = true
    elseif header_seen and ln:find("|", 1, true) then
      local cells = {}
      for cell in (ln .. "|"):gmatch("([^|]*)|") do
        cells[#cells + 1] = vim.trim(cell)
      end
      if #cells >= 4 then
        local secondary = cells[1]:sub(-1) == "*"
        local day = secondary and vim.trim(cells[1]:sub(1, -2)) or cells[1]
        records[#records + 1] = {
          title = cells[2],
          raw_title = corkboard.raw_title(cells[2]),
          day_cell = day,
          secondary = secondary,
          fields = { day = day, title = cells[2] },
        }
      end
    end
  end
  return records
end

-- Only primary day cells are writable; secondary (`also:`) placements are
-- read-only here — edit the scene YAML instead. Values may be numbers or,
-- on ordinal axes, any non-empty coordinate string.
function M.diff(old_recs, new_recs)
  local function key(r)
    return r.title
  end
  local counts = {}
  for _, r in ipairs(old_recs) do
    counts[key(r)] = (counts[key(r)] or 0) + 1
  end
  for _, r in ipairs(new_recs) do
    counts[key(r)] = (counts[key(r)] or 0) - 1
  end
  for k, n in pairs(counts) do
    if n ~= 0 then
      return nil, ("cannot add or remove timeline rows (%s) — edit days instead"):format(k)
    end
  end

  local ops = {}
  local old_by_key = {}
  for _, r in ipairs(old_recs) do
    old_by_key[key(r)] = r
  end
  for _, nr in ipairs(new_recs) do
    local orr = old_by_key[key(nr)]
    local old_day = orr.day_cell
    local new_day = nr.day_cell
    if old_day ~= new_day and orr.secondary then
      return nil,
        ("%s is an also: placement — edit it in the scene YAML, not this sheet"):format(nr.title)
    end
    if old_day ~= new_day then
      local value = nil
      if new_day ~= "·" and new_day ~= "" then
        value = tonumber(new_day)
        if not value then
          value = new_day
        end
      end
      ops[#ops + 1] = {
        op = "set_field",
        rel = nil,
        raw_title = orr.raw_title,
        key = "day",
        value = value,
      }
    end
  end
  return ops
end

return M
