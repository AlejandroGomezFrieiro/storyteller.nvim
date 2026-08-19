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
local meta = require("storyteller.meta")

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
        out[#out + 1] = l
      end
    end
  else
    local globs = vim.fn.glob(dir .. "/**/*.md", false, true)
    for _, p in ipairs(globs) do
      out[#out + 1] = p
    end
  end
  local files = {}
  for _, p in ipairs(out) do
    local rel = vim.fn.fnamemodify(p, ":.")
    if not is_excluded(rel) then
      files[#files + 1] = p
    end
  end
  table.sort(files, function(a, b)
    return vim.fn.fnamemodify(a, ":t") < vim.fn.fnamemodify(b, ":t")
  end)
  return files
end

-- Extract per-scene info from a chapter file's lines.
-- A scene starts at a `## ` heading (top-level H2) and runs to the next one
-- (or EOF). Metadata merges chapter frontmatter + inline bullets + scene YAML.
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

  local h1
  for _, ln in ipairs(lines) do
    local h = ln:match("^#%s+(.*)$")
    if h then
      h1 = h
      break
    end
  end
  if h1 then
    local num, after = h1:match("^[Cc]hapter%s+(%d+)%s*(.*)$")
    if num then
      info.number = tonumber(num)
      after = after or ""
      after = after:gsub("^%s+", "")
      after = after:gsub("^[%-–—:%.]+", "")
      after = after:gsub("^%s+", ""):gsub("%s+$", "")
      info.title = (after ~= "" and after) or h1
    elseif h1 ~= "" then
      info.title = h1:gsub("^%s+", ""):gsub("%s+$", "")
    end
  end

  -- Target: frontmatter `target:` first, else a `# Target:` / `> Target:` line.
  local doc = meta.chapter(path)
  if doc and doc.meta.target ~= nil then
    info.target = doc.meta.target
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
  local cur = nil
  local n = 0
  for i, ln in ipairs(lines) do
    local h2 = ln:match("^##%s+(.*)$")
    if h2 then
      if cur then
        cur.end_line = i - 1
        info.scenes[#info.scenes + 1] = cur
      end
      n = n + 1
      cur = {
        path = path,
        title = h2,
        number = n,
        start_line = i,
        end_line = nil,
      }
    end
  end
  if cur then
    cur.end_line = #lines
    info.scenes[#info.scenes + 1] = cur
  end

  for _, scene in ipairs(info.scenes) do
    local block = meta.scene_block(lines, scene.start_line, scene.end_line)
    local inline = meta.inline(lines, scene.start_line, scene.end_line)
    scene.inline = inline
    scene.yaml = block
    scene.meta = vim.tbl_extend("force", {}, doc.meta, inline, block.meta)
    scene.id = block.meta.id
    scene.content_start = block.content_start
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
  local name = title:match("^([^—–:]+)") or title
  name = name:gsub("%s+$", "")
  local doc = meta.chapter(path)
  local names = (doc and doc.meta.names) or {}
  if #names == 0 then
    names = { name }
  end
  return { path = path, title = title, name = name, names = names, meta = doc and doc.meta or {} }
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
    out[#out + 1] = parse_chapter(p)
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
      out[#out + 1] = sc
    end
  end
  return out
end

local function count_prose(lines, start_line, end_line)
  local count = 0
  local in_fence = false
  for line_number = start_line, end_line do
    local line = lines[line_number] or ""
    if line:match("^```") then
      in_fence = not in_fence
    elseif not in_fence
      and not line:match("^%s*#")
      and not line:match("^%s*-%s*%*%*[%a ]+%*%*:%s*") then
      for _ in line:gmatch("%S+") do
        count = count + 1
      end
    end
  end
  return count
end

M.scene_words = function(sc)
  local lines = vim.fn.readfile(sc.path)
  local block = sc.yaml or meta.scene_block(lines, sc.start_line, sc.end_line or #lines)
  return count_prose(lines, block.content_start or (sc.start_line + 1), sc.end_line or #lines)
end

M.chapter_words = function(ch)
  local total = 0
  for _, sc in ipairs(ch.scenes) do
    total = total + (sc.words or M.scene_words(sc))
  end
  local lines = vim.fn.readfile(ch.path)
  local first = ch.scenes[1]
  local start = 1
  if lines[1] == "---" then
    for i = 2, #lines do
      if lines[i] == "---" then
        start = i + 1
        break
      end
    end
  end
  total = total + count_prose(lines, start, first and first.start_line - 1 or #lines)
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
      cards[#cards + 1] = parse_reference(p)
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
      out[#out + 1] = c
    end
  end
  return out
end

-- --- Navigation helpers -----------------------------------------------------

-- The scene under the cursor, if any.
M.current_scene = function(prj)
  prj = prj or project.current()
  if not prj then
    return nil
  end
  local file = vim.api.nvim_buf_get_name(0)
  local cursor = vim.api.nvim_win_get_cursor(0)[1]
  for _, scene in ipairs(M.scenes(prj)) do
    if scene.path == file and scene.start_line <= cursor and cursor <= (scene.end_line or math.huge) then
      return scene
    end
  end
  return nil
end

-- Open a scene at its heading line.
M.open_scene = function(scene)
  vim.cmd("edit " .. vim.fn.fnameescape(scene.path))
  vim.api.nvim_win_set_cursor(0, { scene.start_line, 0 })
  vim.cmd("normal! zt")
end

M.list_md = list_md
M.parse_chapter = parse_chapter

return M
