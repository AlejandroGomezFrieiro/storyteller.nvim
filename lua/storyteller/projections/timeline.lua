-- storyteller.projections.timeline
-- Story time as an editable table (docs/projections.md): one row per scene
-- ordered by numeric `day:`. Editing the day cell retimes the scene; the row
-- order itself always follows the days, so row moves normalize away.

local index = require("storyteller.index")
local corkboard = require("storyteller.projections.corkboard")

local M = {}

local COLS = { "day", "title", "pov", "words" }

function M.render(prj)
  local entries = index.timeline(prj)
  corkboard.disambiguate(entries)
  local rows = {}
  local widths = { day = 3, title = 5, pov = 3, words = 5 }
  for _, sc in ipairs(entries) do
    local m = sc.meta or {}
    local day = m.day ~= nil and tostring(m.day) or (m.time and tostring(m.time) or "·")
    if m.day == nil and tonumber(m.time) then
      day = tostring(tonumber(m.time))
    end
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

  local function line(cells, pad_char)
    local out = {}
    for _, c in ipairs(COLS) do
      out[#out + 1] = cells[c] .. string.rep(pad_char or " ", widths[c] - #cells[c])
    end
    return table.concat(out, " | ")
  end

  local lines = {
    "# Timeline · story time",
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
      fields = { day = row.cells.day, title = row.cells.title },
      lnum = #lines,
      scene = row.scene,
    }
  end
  return { lines = lines, records = records }
end

-- Parse rows back out of edited text. Identity is the (disambiguated) title.
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
        records[#records + 1] = {
          title = cells[2],
          raw_title = corkboard.raw_title(cells[2]),
          day_cell = cells[1],
          fields = { day = cells[1], title = cells[2] },
        }
      end
    end
  end
  return records
end

-- Only the day cell is writable; anything else is ignored except identity
-- edits, which cannot be expressed here.
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
    if old_day ~= new_day then
      local value = nil
      if new_day ~= "·" and new_day ~= "" then
        value = tonumber(new_day)
        if not value then
          return nil, ("day must be a number or · (got %q for %s)"):format(new_day, nr.title)
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
