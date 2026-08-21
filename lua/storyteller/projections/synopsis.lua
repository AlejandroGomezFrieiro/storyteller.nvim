-- storyteller.projections.synopsis
-- The synopsis outliner (roadmap #3): chapters and scenes as headings, each
-- followed by its `synopsis:` prose. Editing the prose writes the field back;
-- headings are structural anchors and cannot be renamed here (v2).

local index = require("storyteller.index")
local corkboard = require("storyteller.projections.corkboard")

local M = {}

local function synopsis_lines(value)
  if value == nil or value == "" then
    return {}
  end
  if type(value) == "table" then
    local out = {}
    for _, v in ipairs(value) do
      out[#out + 1] = tostring(v)
    end
    return out
  end
  local out = {}
  for ln in tostring(value):gmatch("([^\n]*)\n?") do
    if ln ~= "" or #out > 0 then
      out[#out + 1] = ln
    end
  end
  while out[#out] == "" do
    out[#out] = nil
  end
  return out
end

function M.render(prj)
  corkboard.disambiguate(index.scenes(prj))
  local lines = { "# Synopsis", "" }
  local records = {}

  local function emit(kind, heading, value, scene, path)
    local start = #lines + 1
    lines[#lines + 1] = heading
    local prose = synopsis_lines(value)
    for _, pl in ipairs(prose) do
      lines[#lines + 1] = pl
    end
    lines[#lines + 1] = ""
    records[#records + 1] = {
      kind = kind,
      scene = scene,
      path = path,
      start = start,
      stop = #lines,
      prose = prose,
    }
  end

  for _, ch in ipairs(index.chapters(prj)) do
    local doc = require("storyteller.meta").chapter(ch.path)
    emit(
      "chapter",
      "# " .. (ch.title or vim.fn.fnamemodify(ch.path, ":t")),
      doc and doc.meta and doc.meta.synopsis or nil,
      nil,
      ch.path
    )
    for _, sc in ipairs(ch.scenes) do
      emit("scene", "## " .. (sc._label or sc.title or "Untitled"), sc.meta.synopsis, sc, sc.path)
    end
  end
  return { lines = lines, records = records }
end

-- Parse headings + their prose blocks. The `# Synopsis` banner is not a
-- record; chapter H1s and scene H2s are.
function M.parse(lines)
  local records = {}
  local heads = {}
  for i, ln in ipairs(lines) do
    if ln:match("^##%s+") or (ln:match("^#%s+") and not ln:find("^# Synopsis")) then
      heads[#heads + 1] = { lnum = i, text = ln }
    end
  end
  for n, h in ipairs(heads) do
    local stop = (heads[n + 1] and heads[n + 1].lnum - 1) or #lines
    local prose = {}
    for i = h.lnum + 1, stop do
      prose[#prose + 1] = lines[i] or ""
    end
    while prose[#prose] == "" do
      prose[#prose] = nil
    end
    local kind = h.text:match("^#%s+") and "chapter" or "scene"
    records[#records + 1] = {
      kind = kind,
      heading = h.text,
      title = vim.trim(h.text:gsub("^#+%s+", "")),
      raw_title = corkboard.raw_title(vim.trim(h.text:gsub("^#+%s+", ""))),
      prose = prose,
      start = h.lnum,
      stop = stop,
    }
  end
  return records
end

function M.diff(old_recs, new_recs, prj)
  local counts = {}
  for _, r in ipairs(old_recs) do
    counts[r.heading] = (counts[r.heading] or 0) + 1
  end
  for _, r in ipairs(new_recs) do
    counts[r.heading] = (counts[r.heading] or 0) - 1
  end
  for k, n in pairs(counts) do
    if n ~= 0 then
      return nil, ("cannot add, remove, or rename headings (%s) in the synopsis"):format(k)
    end
  end

  -- Parse records carry no file identity; resolve chapter paths through the
  -- index by heading text.
  local chapter_paths = {}
  if prj then
    for _, ch in ipairs(require("storyteller.index").chapters(prj)) do
      chapter_paths[ch.title or ""] = ch.path
    end
  end

  local ops = {}
  local old_by_heading = {}
  for _, r in ipairs(old_recs) do
    old_by_heading[r.heading] = r
  end
  for _, nr in ipairs(new_recs) do
    local orr = old_by_heading[nr.heading]
    local old_text = table.concat(orr.prose, "\n")
    local new_text = table.concat(nr.prose, "\n")
    if old_text ~= new_text then
      local value = new_text ~= "" and new_text or nil
      if nr.kind == "chapter" then
        ops[#ops + 1] = {
          op = "set_chapter_field",
          path = chapter_paths[orr.raw_title or ""],
          key = "synopsis",
          value = value,
        }
      else
        ops[#ops + 1] = {
          op = "set_field",
          rel = nil,
          path = nil,
          raw_title = orr.raw_title,
          key = "synopsis",
          value = value,
        }
      end
    end
  end
  return ops
end

return M
