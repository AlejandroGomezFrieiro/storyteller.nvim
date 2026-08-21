-- storyteller.projections.metasheet
-- One row per scene, one writable column per tracked field. Built for
-- visual-block edits across many scenes at once (docs/projections.md).

local index = require("storyteller.index")
local corkboard = require("storyteller.projections.corkboard")

local M = {}

local COLS = { "status", "pov", "location", "day", "target" }

local function display(v)
  if v == nil or v == "" then
    return "·"
  end
  return corkboard.stringify(v)
end

function M.render(prj)
  local scenes = index.scenes(prj)
  corkboard.disambiguate(scenes)
  local widths, rows = {}, {}
  for _, c in ipairs({ "scene", unpack(COLS) }) do
    widths[c] = #c
  end
  for _, sc in ipairs(scenes) do
    local m = sc.meta or {}
    local id = vim.fn.fnamemodify(sc.path, ":t") .. " :: " .. (sc._label or sc.title or "Untitled")
    local cells = { scene = id }
    for _, c in ipairs(COLS) do
      cells[c] = display(m[c])
      widths[c] = math.max(widths[c], vim.fn.strdisplaywidth(cells[c]))
    end
    widths.scene = math.max(widths.scene, vim.fn.strdisplaywidth(id))
    rows[#rows + 1] = { scene = sc, cells = cells }
  end

  local function line(cells, pad_char)
    local out = {}
    for _, c in ipairs({ "scene", unpack(COLS) }) do
      out[#out + 1] = cells[c] .. string.rep(pad_char or " ", widths[c] - #cells[c])
    end
    return table.concat(out, " | ")
  end

  local header_cells = { scene = "scene" }
  for _, c in ipairs(COLS) do
    header_cells[c] = c
  end
  local sep = {}
  for _, c in ipairs({ "scene", unpack(COLS) }) do
    sep[#sep + 1] = string.rep("-", widths[c])
  end

  local lines = {
    "# Metadata sheet · " .. #rows .. " scene" .. (#rows == 1 and "" or "s"),
    "",
    line(header_cells),
    table.concat(sep, "-+-"),
  }
  local records = {}
  for _, row in ipairs(rows) do
    lines[#lines + 1] = line(row.cells)
    local fields = {}
    for _, c in ipairs(COLS) do
      fields[c] = row.cells[c]
    end
    records[#records + 1] = {
      id = row.cells.scene,
      title = row.cells.scene:match(":: (.+)$"),
      raw_title = row.scene.title,
      fields = fields,
      lnum = #lines,
    }
  end
  return { lines = lines, records = records }
end

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
      if #cells >= 6 then
        local fields = {}
        for i, c in ipairs(COLS) do
          fields[c] = cells[i + 1]
        end
        records[#records + 1] = {
          id = cells[1],
          title = cells[1]:match(":: (.+)$"),
          raw_title = corkboard.raw_title(cells[1]:match(":: (.+)$") or ""),
          fields = fields,
        }
      end
    end
  end
  return records
end

-- Writable columns map to set_field; the scene identity column cannot change.
function M.diff(old_recs, new_recs)
  local counts = {}
  for _, r in ipairs(old_recs) do
    counts[r.id] = (counts[r.id] or 0) + 1
  end
  for _, r in ipairs(new_recs) do
    counts[r.id] = (counts[r.id] or 0) - 1
  end
  for k, n in pairs(counts) do
    if n ~= 0 then
      return nil, ("cannot add, remove, or rename rows (%s) in the metadata sheet"):format(k)
    end
  end

  local ops = {}
  local old_by_id = {}
  for _, r in ipairs(old_recs) do
    old_by_id[r.id] = r
  end
  for _, nr in ipairs(new_recs) do
    local orr = old_by_id[nr.id]
    for _, c in ipairs(COLS) do
      if (orr.fields[c] or "") ~= (nr.fields[c] or "") then
        local writable = nr.fields[c] ~= "·"
        if not writable and (orr.fields[c] or "") ~= "·" then
          ops[#ops + 1] = {
            op = "set_field",
            raw_title = orr.raw_title,
            key = c,
            value = nil,
          }
        elseif writable then
          ops[#ops + 1] = {
            op = "set_field",
            raw_title = orr.raw_title,
            key = c,
            value = corkboard.parse_value(nr.fields[c]),
          }
        end
      end
    end
  end
  return ops
end

return M
