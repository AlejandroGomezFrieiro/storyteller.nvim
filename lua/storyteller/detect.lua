-- storyteller.detect
-- Kindling-style reference detection over a project.
--
-- Builds a lower-cased name index over every reference card (full name and
-- aliases), scans scene prose with 1..3-word n-grams (trimming trailing ASCII
-- punctuation), and yields per-scene link suggestions with confidence:
--   * characters: full name        -> 1.0
--   * characters: unique first name-> 0.7
--   * locations/items/orgs: full   -> 1.0
--
-- Suggestions already linked (chars/locs/items/orgs) or in `ignore` are
-- filtered out.

local project = require("storyteller.project")
local metadata = require("storyteller.metadata")
local index = require("storyteller.index")

local M = {}

-- ASCII punctuation ords we treat as strippable (excludes apostrophe 0x27 so
-- "Alice's" is not trimmed into "alice", per the Kindling algorithm).
local PUNCT = {}
for i = 33, 126 do
  local c = string.char(i)
  if not c:match("%w") and i ~= 39 then
    PUNCT[i] = true
  end
end

local function strip(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Trim leading/trailing ASCII punctuation (but keep apostrophes inside words).
local function trim_punct(s)
  while s ~= "" do
    local b = string.byte(s, 1)
    if PUNCT[b] then
      s = s:sub(2)
    else
      break
    end
  end
  while s ~= "" do
    local b = string.byte(s, -1)
    if PUNCT[b] then
      s = s:sub(1, -2)
    else
      break
    end
  end
  return s
end

local function first_word(s)
  return (s:match("^(%S+)") or "")
end

-- --- Public API ------------------------------------------------------------

-- Build { name_lower -> { name, reference, confidence } } over all references.
-- `reference` is normalized: index cards lack a `.name`, so we add the
-- canonical full name (names[1]) for `link`/`dismiss` to push into frontmatter.
M.build_index = function(prj)
  prj = prj or project.current()
  local refs = index.all_references(prj)
  local bykey = {}
  local first_counts = {}

  local function canon_name(ref)
    local names = ref.names or {}
    if #names > 0 then
      return strip(tostring(names[1]))
    end
    return strip(tostring(ref.title or ""))
  end

  local function normalize(ref)
    return {
      name = canon_name(ref),
      type = ref.type,
      path = ref.path,
      title = ref.title,
      names = ref.names,
      meta = ref.meta,
    }
  end

  local function put(key, name, ref, confidence)
    local cur = bykey[key]
    if (not cur) or confidence > cur.confidence then
      bykey[key] = { name = name, reference = normalize(ref), confidence = confidence }
    end
  end

  -- First pass: full names (+ first-name uniqueness counts).
  for _, ref in ipairs(refs) do
    local names = ref.names or {}
    if #names > 0 then
      local full = strip(tostring(names[1]))
      if full ~= "" then
        put(full:lower(), full, ref, 1.0)
        if ref.type == "characters" then
          local first = first_word(full):lower()
          if first ~= "" then
            first_counts[first] = (first_counts[first] or 0) + 1
          end
        end
      end
    end
  end

  -- Aliases: treat each as a full-name spelling (confidence 1.0).
  for _, ref in ipairs(refs) do
    local names = ref.names or {}
    for i = 2, #names do
      local n = strip(tostring(names[i]))
      if n ~= "" then
        put(n:lower(), n, ref, 1.0)
      end
    end
  end

  -- Unique first names for characters (0.7), unless identical to one-word full names.
  for _, ref in ipairs(refs) do
    if ref.type == "characters" and ref.names and #ref.names > 0 then
      local full = strip(tostring(ref.names[1]))
      local first = first_word(full):lower()
      if first ~= "" and first ~= full:lower() and first_counts[first] == 1 then
        put(first, ref.names[1], ref, 0.7)
      end
    end
  end

  return bykey
end

-- Tokenize a scene's prose (skips heading, bullet metadata, blockquotes, fences).
local function scene_tokens(sc)
  local lines = vim.fn.readfile(sc.path)
  local toks = {}
  for i = sc.start_line, (sc.end_line or #lines) do
    local ln = lines[i]
    if ln then
      local marker = ln:match("^%s*(.)")
      if not (i == sc.start_line or marker == "-" or marker == "*" or marker == ">" or marker == "#" or marker == "`") then
        for w in ln:gmatch("%S+") do
          toks[#toks + 1] = w
        end
      end
    end
  end
  return toks
end

-- Suggestions for one scene (list of { name, confidence, type, reference, path }).
M.detect_scene = function(sc, prj, idx)
  prj = prj or project.current()
  idx = idx or M.build_index(prj)

  local mdoc = metadata.read(sc.path)
  local m = mdoc and mdoc.meta or {}
  local linked, ignored = {}, {}
  for _, k in ipairs({ "chars", "locs", "items", "orgs" }) do
    for _, v in ipairs(m[k] or {}) do
      linked[strip(tostring(v)):lower()] = true
    end
  end
  for _, v in ipairs(m.ignore or {}) do
    ignored[strip(tostring(v)):lower()] = true
  end

  local toks = scene_tokens(sc)
  local sugs, used = {}, {}
  for w = 3, 1, -1 do
    for i = 1, #toks - w + 1 do
      local parts = {}
      for j = i, i + w - 1 do
        parts[#parts + 1] = toks[j]
      end
      local key = trim_punct(table.concat(parts, " ")):lower()
      local entry = idx[key]
      if entry then
        local short = entry.name:lower()
        local full = (entry.reference.title or entry.name):lower()
        if (not used[short]) and (not linked[short]) and (not linked[full])
          and (not ignored[short]) and (not ignored[full]) then
          sugs[#sugs + 1] = {
            name = entry.name,
            confidence = entry.confidence,
            type = entry.reference.type,
            reference = entry.reference,
            path = sc.path,
          }
          used[short] = true
        end
      end
    end
  end
  table.sort(sugs, function(a, b)
    return a.confidence > b.confidence
  end)
  return sugs
end

-- { scene_path -> suggestions } across the whole project.
M.detect_project = function(prj)
  prj = prj or project.current()
  local idx = M.build_index(prj)
  local out = {}
  for _, sc in ipairs(index.scenes(prj)) do
    local existing = out[sc.path] or {}
    for _, s in ipairs(M.detect_scene(sc, prj, idx)) do
      table.insert(existing, s)
    end
    out[sc.path] = existing
  end
  return out
end

local FIELD = {
  character = "chars",
  characters = "chars",
  location = "locs",
  locations = "locs",
  item = "items",
  items = "items",
  organization = "orgs",
  organizations = "orgs",
}

-- Link a reference into the scene's frontmatter.
M.link = function(scene_path, ref)
  local field = FIELD[ref and ref.type] or "chars"
  metadata.push(scene_path, field, ref.name)
end

-- Dismiss a detected name for a scene (adds to `ignore`).
M.dismiss = function(scene_path, name)
  metadata.push(scene_path, "ignore", name)
end

-- Auto-link confident suggestions (confidence >= 0.9) in one scene.
M.link_all = function(scene, prj)
  prj = prj or project.current()
  local linked = 0
  for _, s in ipairs(M.detect_scene(scene, prj)) do
    if s.confidence >= 0.9 then
      M.link(scene.path, s.reference)
      linked = linked + 1
    end
  end
  return linked
end

return M