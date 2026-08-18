-- storyteller.index
-- Scans a project's on-disk structure into a normalized index:
--   chapters  -> { path, filename, number, title, target, scenes[] }
--   scenes    -> { path, title, number, meta, start_line, end_line }
--   references-> { characters, locations, items, organizations }
--
-- Reads only markdown; nothing is written here. `_`-prefixed dirs/files
-- (and files/dirs under `.` / hidden) are treated as "unused/excluded".

local project = require("storyteller.project")
local config = require("storyteller.config")

local M = {}

local function is_excluded(relpath)
  for part in relpath:gmatch("[^/]+") do
    if part:sub(1, 1) == "_" or part:sub(1, 1) == "." then
      return true
    end
  end
  return false
end

-- rg if configured, else glob fallback. Returns absolute file paths.
local function list_md(dir)
  if not dir or vim.fn.isdirectory(dir) ~= 1 then
    return {}
  end
  local rg = config.get().rg
  local out = {}
  if rg then
    local lines = vim.fn.systemlist({ rg, "--files", "--glob", "*.md", dir })
    for _, l in ipairs(lines) do
      if l ~= "" then
        table.insert(out, l)
      end
    end
  else
    local globs = vim.fn.glob(dir .. "/**/*.md", false, true)
    for _, p in ipairs(globs) do
      table.insert(out, p)
    end
  end
  local files = {}
  for _, p in ipairs(out) do
    local rel = vim.fn.fnamemodify(p, ":.")
    if not is_excluded(rel) then
      table.insert(files, p)
    end
  end
  table.sort(files, function(a, b)
    return vim.fn.fnamemodify(a, ":t") < vim.fn.fnamemodify(b, ":t")
  end)
  return files
end

local function flatten(p, ...)
  return table.concat({ p, ... }, "/")
end

-- Extract per-scene info from a chapter file's lines.
-- A scene starts at a `## ` heading (top-level H2) and runs to the next one
-- (or EOF). Metadata merges frontmatter fields plus inline `- **Key:**` lines.
local function parse_chapter(path)
  local lines = vim.fn.readfile(path)
  local info = {
    path = path,
    filename = vim.fn.fnamemodify(path, ":t"),
    number = nil,
    title = nil,
    target = nil,
    scenes = {},
  }
  -- H1 title + number
    -- H1 title + number (scan the whole file — frontmatter may precede it)
  local h1
  for _, ln in ipairs(lines) do
    local h = ln:match("^#%s+(.*)$")
    if h then
      h1 = h
      break
    end
  end
  if h1 then
    local num, after = h1:match("^Chapter%s+(%d+)%s*[:.–—-]?(.-)%s*$")
    if num then
      info.number = tonumber(num)
      if after then
        info.title = (after:gsub("^%s+", ""):gsub("%s+$", ""))
      end
      info.title = (info.title ~= "" and info.title) or h1
    elseif h1 ~= "" then
      info.title = (h1:gsub("^%s+", ""):gsub("%s+$", ""))
    end
  end

  -- Target: frontmatter `target:` first (most reliable), else `# Target:`
  local meta = require("storyteller.metadata").read(path)
  if meta and meta.meta.target ~= nil then
    info.target = meta.meta.target
  else
    for _, ln in ipairs(lines) do
      local t = ln:match("^%s*[#>*]%s*Target:%s*(%d+)")
      if t then
        info.target = tonumber(t)
        break
      end
    end
  end

  -- Build scenes from `## ` headings at column 0.
  local in_scene = false
  local cur = nil
  local n = 0
  for i, ln in ipairs(lines) do
    local h2 = ln:match("^##%s+(.*)$")
    if h2 and not h2:match("^#") then
      -- close previous
      if cur then
        cur.end_line = i - 1
        table.insert(info.scenes, cur)
      end
      n = n + 1
      cur = {
        path = path,
        title = h2,
        number = n,
        start_line = i,
        end_line = nil,
        meta = { pov = nil, location = nil },
      }
      in_scene = true
    elseif in_scene and cur and ln ~= "" then
      local k, v = ln:match("^%s*-%s*%*%*%s*([A-Za-z]+)%s*%*%*:%s*(.*)$")
      if k and v then
        cur.meta[k:lower()] = v
      elseif ln:match("^```$") then
        -- ignore code fences inside a scene
      end
    end
  end
  if cur then
    cur.end_line = #lines
    table.insert(info.scenes, cur)
  end
  return info
end

-- A reference card: H1/H2 title (template cards use `## Name — Role`), plus
-- `names:` aliases from frontmatter. The primary name is the leading token
-- before an em/en-dash or colon.
local function parse_reference(path)
  local lines = vim.fn.readfile(path)
  local title = nil
  for i = 1, math.min(#lines, 16) do
    local h = lines[i]:match("^#+%s+(.*)$")
    if h then
      title = h
      break
    end
  end
  title = title or vim.fn.fnamemodify(path, ":t:r"):gsub("^_", "")
  -- primary name: stop at ` — ` / `–` / `:`
  local name = title:match("^([^—–:]+)") or title
  name = name:gsub("%s+$", "")
  local meta = require("storyteller.metadata").read(path)
  local names = (meta and meta.meta.names) or {}
  if #names == 0 then
    names = { name }
  end
  return { path = path, title = title, name = name, names = names, meta = meta and meta.meta or {} }
end

-- --- Public API -------------------------------------------------------------

-- Chapters in a project (lexical file order).
M.chapters = function(prj)
  prj = prj or project.current()
  if not prj then
    return {}
  end
  local out = {}
  for _, p in ipairs(list_md(prj.chapters)) do
    table.insert(out, parse_chapter(p))
  end
  return out
end

-- Flat list of scenes across all chapters.
M.scenes = function(prj)
  prj = prj or project.current()
  local out = {}
  for _, ch in ipairs(M.chapters(prj)) do
    for _, sc in ipairs(ch.scenes) do
      sc.chapter = ch
      sc.words = M.scene_words(sc)
      table.insert(out, sc)
    end
  end
  return out
end

M.scene_words = function(sc)
  local lines = vim.fn.readfile(sc.path)
  if sc.end_line then
    lines = vim.list_slice(lines, sc.start_line, sc.end_line)
  else
    lines = vim.list_slice(lines, sc.start_line)
  end
  local body = table.concat(lines, " ")
  local count = 0
  for _ in body:gmatch("%S+") do
    count = count + 1
  end
  return count
end

M.chapter_words = function(ch)
  local total = 0
  for _, sc in ipairs(ch.scenes) do
    total = total + (sc.words or M.scene_words(sc))
  end
  -- include lines above first scene too
  local lines = vim.fn.readfile(ch.path)
  local head = {}
  local first = ch.scenes[1]
  local upto = first and first.start_line - 1 or #lines
  for i = 1, upto do
    table.insert(head, lines[i])
  end
  local body = table.concat(head, " ")
  for _ in body:gmatch("%S+") do
    total = total + 1
  end
  return total
end

-- Reference cards by type.
M.references = function(prj)
  prj = prj or project.current()
  local types = {
    characters = prj.characters,
    locations = prj.locations,
    items = prj.items,
    organizations = prj.organizations,
  }
  local out = {}
  for t, dir in pairs(types) do
    local cards = {}
    for _, p in ipairs(list_md(dir)) do
      table.insert(cards, parse_reference(p))
    end
    out[t] = cards
  end
  return out
end

-- Flat list of all references with their type.
M.all_references = function(prj)
  prj = prj or project.current()
  local out = {}
  for t, cards in pairs(M.references(prj)) do
    for _, c in ipairs(cards) do
      c.type = t
      table.insert(out, c)
    end
  end
  return out
end

M.list_md = list_md
M.parse_chapter = parse_chapter

return M