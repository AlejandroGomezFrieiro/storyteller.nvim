-- storyteller.templates
-- Load and apply story-structure templates shipped as JSON (`templates/*.json`)
-- either in the plugin package or a user override dir. Templates port Kindling's
-- bundled structures into chapter scaffolds (one chapter file per beat, scenes
-- as `## ` headings).

local config = require("storyteller.config")
local project = require("storyteller.project")
local meta = require("storyteller.meta")

local M = {}

local function join(...)
  return table.concat({ ... }, "/")
end

local function dirs()
  local out = {}
  local seen = {}
  local function add(dir)
    if dir and dir ~= "" and vim.fn.isdirectory(dir) == 1 and not seen[dir] then
      seen[dir] = true
      out[#out + 1] = dir
    end
  end
  add(config.get().templates_dir)
  for _, base in ipairs(vim.opt.runtimepath:get() or {}) do
    if base ~= "" then
      add(join(base, "templates"))
    end
  end
  add(join(vim.fn.getcwd(), "templates"))
  return out
end

local function template_files()
  local files = {}
  local seen = {}
  for _, dir in ipairs(dirs()) do
    for _, p in ipairs(vim.fn.glob(dir .. "/*.json", false, true) or {}) do
      local base = vim.fn.fnamemodify(p, ":t")
      if not seen[base] then
        seen[base] = true
        files[#files + 1] = p
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

M.load = function(name)
  if not name then
    return nil
  end
  local stem = name:gsub("%.json$", "")
  for _, dir in ipairs(dirs()) do
    local p = join(dir, stem .. ".json")
    if vim.loop.fs_stat(p) then
      return decode(p)
    end
  end
  for _, p in ipairs(template_files()) do
    local t = decode(p)
    if t and (t.id == name or t.name == name) then
      return t
    end
  end
  return nil
end

M.list = function()
  local names = {}
  for _, p in ipairs(template_files()) do
    local t = decode(p)
    if t and t.id then
      names[#names + 1] = t.id
    end
  end
  table.sort(names)
  return names
end

M.entries = function()
  local out = {}
  local seen = {}
  for _, p in ipairs(template_files()) do
    local t = decode(p)
    if t and t.id and not seen[t.id] then
      seen[t.id] = true
      out[#out + 1] = {
        value = t,
        display = ("%s · %s"):format(t.id, t.name or ""),
        hint = t.description,
      }
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
  s = s:gsub("%s+", "-")
  return s
end

local function scene_lines(scene)
  local lines = { "", "## " .. tostring(scene.title) }
  if scene.synopsis and scene.synopsis ~= "" then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "> **Synopsis:** " .. scene.synopsis
  end
  lines[#lines + 1] = ""
  return lines
end

local function write_beat(path, beat, act_number)
  if vim.loop.fs_stat(path) then
    return false
  end
  local lines = {}
  vim.list_extend(lines, meta.serde.encode_frontmatter({ type = "chapter", planning = "flexible" }))
  lines[#lines + 1] = ""
  lines[#lines + 1] = ("# %02d · %s"):format(act_number, tostring(beat.title))
  if beat.synopsis and beat.synopsis ~= "" then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "> " .. beat.synopsis
  end
  for _, scene in ipairs(beat.scenes or {}) do
    vim.list_extend(lines, scene_lines(scene))
  end
  vim.fn.writefile(lines, path)
  return true
end

-- Compute what `apply` would create without writing anything.
function M.plan(prj, name)
  prj = prj or project.current()
  if not prj then
    return nil
  end
  local t = M.load(name)
  if not t then
    return nil
  end
  local created, skipped = {}, {}
  for _i, part in ipairs(t.structure or {}) do
    for _j, beat in ipairs(part.children or {}) do
      local slug = slugify(beat.title)
      if slug == "" then
        slug = "beat"
      end
      local path = join(prj.chapters, slug .. ".md")
      if vim.loop.fs_stat(path) then
        skipped[#skipped + 1] = path
      else
        created[#created + 1] = path
      end
    end
  end
  return { template = t, created = created, skipped = skipped }
end

M.apply = function(prj, name)
  local plan = M.plan(prj, name)
  if not plan then
    vim.notify(("[storyteller] Unknown template: %s"):format(tostring(name)), vim.log.levels.ERROR)
    return nil
  end
  vim.fn.mkdir(plan.created and plan.created[1] and vim.fn.fnamemodify(plan.created[1], ":h") or prj.chapters, "p")
  local created, skipped = 0, 0
  for _i, part in ipairs(plan.template.structure or {}) do
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
      :format(plan.template.id, created, skipped),
    vim.log.levels.INFO
  )
  return { created = created, skipped = skipped, template = plan.template }
end

M.slugify = slugify

return M
