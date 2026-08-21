-- storyteller.projections.corkboard
-- The corkboard as an editable text projection (docs/projections.md):
-- one card block per scene, in story order. Editing the text edits the
-- project: field lines become scene YAML, card order becomes scene order
-- across chapter files.

local index = require("storyteller.index")

local M = {}

-- Writable field lines, in render order.
M.FIELD_ORDER = {
  "status",
  "pov",
  "location",
  "day",
  "target",
  "beat",
  "goal",
  "conflict",
  "outcome",
  "synopsis",
}

function M.rel(prj, path)
  return (path:gsub("^" .. vim.pesc(prj.root) .. "/", ""))
end

function M.stringify(v)
  if type(v) == "table" then
    local out = {}
    for _, item in ipairs(type(v) == "table" and v or { v }) do
      out[#out + 1] = tostring(item)
    end
    return table.concat(out, ", ")
  end
  return tostring(v)
end

-- Render-time string -> typed value ("", numeric strings, plain strings).
function M.parse_value(s)
  s = vim.trim(s or "")
  if s == "" then
    return nil
  end
  if s:match("^%-?%d+$") or s:match("^%-?%d+%.%d+$") then
    return tonumber(s)
  end
  return s
end

-- Disambiguate duplicate titles within a file; the second occurrence renders
-- ` #2`. Deterministic within a render pair, so identity matching works.
function M.disambiguate(scenes)
  local seen = {}
  for _, sc in ipairs(scenes) do
    local key = sc.path .. "\0" .. (sc.title or "")
    seen[key] = (seen[key] or 0) + 1
    sc._label = sc.title or "Untitled"
    if seen[key] > 1 then
      sc._label = sc._label .. " #" .. seen[key]
    end
  end
end

-- Strip a render disambiguator back to the raw heading text.
function M.raw_title(label)
  return (label:gsub(" #%d+$", ""))
end

function M.render(prj)
  local scenes = index.scenes(prj)
  M.disambiguate(scenes)
  local lines = {
    "# Corkboard · " .. #scenes .. " scene" .. (#scenes == 1 and "" or "s"),
    "",
  }
  local records = {}
  for _, sc in ipairs(scenes) do
    local m = sc.meta or {}
    local start = #lines + 1
    lines[#lines + 1] = "## " .. sc._label
    -- The file line is the oil.nvim-style editable address: change it (and/or
    -- move the card) to relocate a scene across chapter files.
    lines[#lines + 1] = "file: " .. M.rel(prj, sc.path)
    for _, key in ipairs(M.FIELD_ORDER) do
      local v = m[key]
      if v ~= nil and v ~= "" then
        lines[#lines + 1] = key .. ": " .. M.stringify(v)
      end
    end
    local target = tonumber(m.target)
    lines[#lines + 1] = "words: " .. (sc.words or 0) .. (target and (" / " .. target) or "")
    lines[#lines + 1] = ""
    records[#records + 1] = {
      title = sc._label,
      raw_title = sc.title,
      fields = { file = M.rel(prj, sc.path) },
      start = start,
    }
  end
  -- Close spans (each card runs to just before the next header).
  for n, r in ipairs(records) do
    r.stop = records[n + 1] and (records[n + 1].start - 1) or #lines
  end
  return { lines = lines, records = records }
end

-- Parse rendered/edited text back into card records. Identity is the title;
-- the `file:` line is the card's address and may be edited to move a scene.
function M.parse(lines)
  local records = {}
  local cur = nil
  for i, ln in ipairs(lines) do
    local title = ln:match("^## (.+)$")
    if title then
      cur = {
        title = vim.trim(title),
        raw_title = M.raw_title(vim.trim(title)),
        fields = {},
        start = i,
      }
      if records[#records] then
        records[#records].stop = i - 1
      end
      records[#records + 1] = cur
    elseif cur then
      local k, v = ln:match("^([%w_]+):%s*(.*)$")
      if k and k ~= "words" then
        cur.fields[k] = vim.trim(v)
      end
    end
  end
  if records[#records] then
    records[#records].stop = #lines
  end
  return records
end

-- Per-file scene sequences implied by a record list.
local function sequences(records)
  local seq = {}
  for _, r in ipairs(records) do
    local rel = r.fields.file
    if not (rel and rel ~= "") then
      return nil, "card " .. r.title .. " has no file: line"
    end
    seq[rel] = seq[rel] or {}
    table.insert(seq[rel], r.raw_title)
  end
  return seq
end

-- Diff baseline cards against edited cards -> ops.
-- Rejects deletions/additions/duplicates rather than guessing intent.
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
      return nil,
        ("cannot %s card %s (cards may only be moved or edited)"):format(
          n > 0 and "removed" or "added",
          k
        )
    end
  end

  local ops = {}

  -- Structural edit: per-file sequences changed (reorder or file move).
  local old_seq, serr = sequences(old_recs)
  if not old_seq then
    return nil, serr
  end
  local new_seq = sequences(new_recs)
  if not new_seq then
    return nil, new_seq
  end
  local structural = false
  for rel, titles in pairs(new_seq) do
    local prev = old_seq[rel] or {}
    if #prev ~= #titles then
      structural = true
      break
    end
    for i, t in ipairs(titles) do
      if prev[i] ~= t then
        structural = true
        break
      end
    end
    if structural then
      break
    end
  end
  if not structural then
    for rel in pairs(old_seq) do
      if not new_seq[rel] then
        structural = true
        break
      end
    end
  end
  if structural then
    ops[#ops + 1] = { op = "reorder", files = new_seq }
  end

  -- Field edits (the file: line is structural, handled above).
  local old_by_key = {}
  for _, r in ipairs(old_recs) do
    old_by_key[key(r)] = r
  end
  for _, nr in ipairs(new_recs) do
    local orr = old_by_key[key(nr)]
    local keys = {}
    for k in pairs(orr.fields) do
      if k ~= "file" then
        keys[k] = true
      end
    end
    for k in pairs(nr.fields) do
      if k ~= "file" then
        keys[k] = true
      end
    end
    for k in pairs(keys) do
      if (orr.fields[k] or "") ~= (nr.fields[k] or "") then
        ops[#ops + 1] = {
          op = "set_field",
          raw_title = orr.raw_title,
          key = k,
          value = M.parse_value(nr.fields[k]),
        }
      end
    end
  end
  return ops
end

return M
