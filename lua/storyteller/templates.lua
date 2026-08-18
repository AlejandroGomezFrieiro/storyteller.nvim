-- storyteller.templates
-- Load and apply story-structure templates shipped as JSON (`templates/*.json`)
-- either in the plugin package or a user override dir. Templates port Kindling's
-- bundled structures into chapter scaffolds (one chapter file per beat, scenes
-- as `## ` headings).

local config = require("storyteller.config")
local project = require("storyteller.project")
local metadata = require("storyteller.metadata")

local M = {}

-- --- Template discovery -----------------------------------------------------

local function join(...)
  return table.concat({ ... }, "/")
end

-- Candidate template dirs: config override first, then every `templates/`
-- directory found on the runtimepath (plugin package usually owns one).
local function dirs()
  local out = {}
  local seen = {}
  local function add(dir)
    if dir and dir ~= "" and vim.fn.isdirectory(dir) == 1 and not seen[dir] then
      seen[dir] = true
      table.insert(out, dir)
    end
  end
  add(config.get().templates_dir)
  local rtp = vim.opt.runtimepath:get() or {}
  for _, base in ipairs(rtp) do
    if base ~= "" then
      add(join(base, "templates"))
    end
  end
  add(join(vim.fn.getcwd(), "templates"))
  return out
end

-- All `*.json` files under the template dirs, de-duplicated by basename with
-- repo/override priority (override dir first).
local function template_files()
  local files = {}
  local seen = {}
  for _, dir in ipairs(dirs()) do
    local globs = vim.fn.glob(dir .. "/" .. "*.json", false, true) or {}
    for _, p in ipairs(globs) do
      local base = vim.fn.fnamemodify(p, ":t")
      if not seen[base] then
        seen[base] = true
        table.insert(files, p)
      end
    end
  end
  return files
end

local function decode(path)
  local ok, data = pcall(vim.json.decode, table.concat(vim.fn.readfile(path), "\n"))
  if not ok or type(data) ~= "table" then
    return nil
  end
  return data
end

-- --- Public API -------------------------------------------------------------

-- Load a template by file stem, `id`, or `name`. Returns the decoded table or
-- nil. Searches override/per-package dirs and falls back to path heuristics.
M.load = function(name)
  if not name then
    return nil
  end
  -- 1. exact file treat (drive name as a stem): templates/<name>.json
  local stem = (name:gsub("%.json$", ""))
  for _, dir in ipairs(dirs()) do
    local p = join(dir, stem .. ".json")
    if vim.loop.fs_stat(p) then
      return decode(p)
    end
  end
  -- 2. scan every known template file for a matching id/name
  for _, p in ipairs(template_files()) do
    local t = decode(p)
    if t then
      if t.id == name or t.name == name then
        return t
      end
    end
  end
  return nil
end

-- Names (id) of every available template.
M.list = function(_prj)
  local names = {}
  for _, p in ipairs(template_files()) do
    local t = decode(p)
    if t and t.id then
      table.insert(names, t.id)
    end
  end
  table.sort(names)
  return names
end

-- Quick summaries for a picker: one entry per available template.
M.entries = function()
  local out = {}
  local seen = {}
  for _, p in ipairs(template_files()) do
    local t = decode(p)
    if t and t.id and not seen[t.id] then
      seen[t.id] = true
      table.insert(out, {
        value = t,
        display = ("%s · %s"):format(t.id, t.name or ""),
        hint = t.description,
      })
    end
  end
  table.sort(out, function(a, b)
    return a.value.id < b.value.id
  end)
  return out
end

local function slugify(s)
  s = (s or ""):lower()
  s = s:gsub("[^%w%s-]", "")
  s = (s:gsub("%s+", "-"))
  return s
end

local function scene_lines(scene)
  local lines = {}
  table.insert(lines, "")
  table.insert(lines, "## " .. tostring(scene.title))
  if scene.synopsis and scene.synopsis ~= "" then
    table.insert(lines, "")
    table.insert(lines, "> **Synopsis:** " .. scene.synopsis)
  end
  table.insert(lines, "")
  return lines
end

-- Scaffold one beat (→ one chapter file) with frontmatter + scene headings.
local function write_beat(path, beat, act_number)
  if vim.loop.fs_stat(path) then
    return false -- skip existing
  end
  local lines = {}
  vim.list_extend(lines, metadata.encode({ type = "chapter", planning = "flexible" }))
  table.insert(lines, "")
  table.insert(lines, ("# %02d · %s"):format(act_number, tostring(beat.title)))
  if beat.synopsis and beat.synopsis ~= "" then
    table.insert(lines, "")
    table.insert(lines, "> " .. beat.synopsis)
  end
  for _, scene in ipairs(beat.scenes or {}) do
    vim.list_extend(lines, scene_lines(scene))
  end
  vim.fn.writefile(lines, path)
  return true
end

-- Apply a template to a project: one chapter per beat under `chapters/`,
-- frontmatter `type: chapter` + `planning: flexible`, scenes as `## ` headings.
-- Skips files that already exist.
M.apply = function(prj, name)
  prj = prj or project.current()
  if not prj then
    vim.notify("[storyteller] Not in a storytelling project.", vim.log.levels.WARN)
    return nil
  end
  local t = M.load(name)
  if not t then
    vim.notify(("[storyteller] Unknown template: %s"):format(tostring(name)), vim.log.levels.ERROR)
    return nil
  end
  vim.fn.mkdir(prj.chapters, "p")
  local created = 0
  local skipped = 0
  for _i, part in ipairs(t.structure or {}) do
    for _j, beat in ipairs(part.children or {}) do
      local slug = slugify(beat.title)
      if slug == "" then
        slug = "beat"
      end
      local path = join(prj.chapters, slug .. ".md")
      if write_beat(path, beat, _i) then
        created = created + 1
      else
        skipped = skipped + 1
      end
    end
  end
  vim.notify(
    ("[storyteller] Template '%s' applied: %d chapters created, %d skipped")
      :format(t.id, created, skipped),
    vim.log.levels.INFO
  )
  return { created = created, skipped = skipped, template = t }
end

M.slugify = slugify

return M