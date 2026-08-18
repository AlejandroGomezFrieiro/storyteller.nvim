-- storyteller.collections
-- Saved filters over scenes ("pov", "location", "status", "planning",
-- "unfinished", "tagged") plus named per-scene collections.
--
--   collections.pick(prj)      choose a predicate -> value -> matching scene
--   collections.run(name, prj) run a single predicate directly
--   collections.collect(prj)   add the scene under the cursor to a named list
--   collections.show()         browse saved named lists like a filter
--
-- Matching honours frontmatter first (`metadata.read`) and falls back to the
-- inline "- **Key:**" lines that `index.scenes` already scraped into
-- `sc.meta`. `collections.saved` is in-memory for now (persistence later).

local project = require("storyteller.project")
local index = require("storyteller.index")
local metadata = require("storyteller.metadata")
local pickers = require("storyteller.pickers")
local config = require("storyteller.config")
local command = require("storyteller.command")

local M = {}

-- name -> list of { path, title, start_line, end_line }
M.saved = {}

local fm_cache = {}

local function doc(path)
  if fm_cache[path] == nil then
    local ok, d = pcall(metadata.read, path)
    fm_cache[path] = ok and d or false
  end
  return fm_cache[path] == false and nil or fm_cache[path]
end

local function not_in_project()
  vim.notify("[storyteller] Not in a storytelling project.", vim.log.levels.WARN)
end

-- Field value for a predicate: frontmatter dominates, inline - **Key:** next.
local function scene_field(sc, key)
  local d = doc(sc.path)
  if d and d.meta[key] ~= nil then
    return d.meta[key]
  end
  return sc.meta and sc.meta[key]
end

local function scene_has_tag(sc, tag)
  local v = scene_field(sc, "tags")
  if type(v) == "table" then
    for _, t in ipairs(v) do
      if tostring(t) == tag then
        return true
      end
    end
    return false
  end
  return v ~= nil and tostring(v) == tag
end

-- True when the scene body contains an unchecked `- [ ]` beat.
local function scene_unfinished(sc)
  local lines = vim.fn.readfile(sc.path)
  if not lines then
    return false
  end
  local last = math.min(sc.end_line or #lines, #lines)
  for i = sc.start_line, last do
    if lines[i] and lines[i]:find("^%s*%-%s*%[%s*%]") then
      return true
    end
  end
  return false
end

-- Distinct candidate values across scenes for a predicate.
local function candidates_for(name, scenes)
  local vals, seen = {}, {}
  local function add(v)
    if v == nil or v == "" then
      return
    end
    if type(v) == "table" then
      for _, item in ipairs(v) do
        add(item)
      end
      return
    end
    local key = tostring(v)
    if key == "" or seen[key] then
      return
    end
    seen[key] = true
    vals[#vals + 1] = key
  end
  for _, sc in ipairs(scenes) do
    add(scene_field(sc, name))
  end
  return vals
end

-- Present a list of scenes in a picker; selecting opens the chapter at the
-- scene's heading line.
M.present = function(scenes, title)
  if #scenes == 0 then
    vim.notify("[storyteller] No matching scenes.", vim.log.levels.INFO)
    return
  end
  local entries = {}
  for _, sc in ipairs(scenes) do
    local ch = sc.chapter or {}
    local done = sc.words or 0
    local target = tostring(ch.target or "")
    local display = ("%s · %s · %s/%s"):format(
      ch.title or vim.fn.fnamemodify(sc.path, ":t:r"),
      sc.title or "",
      done,
      target
    )
    entries[#entries + 1] = { value = sc, display = display }
  end
  pickers.pick_list(entries, {
    prompt_title = "Storyteller · " .. (title or "scenes"),
    on_select = function(sc)
      vim.cmd("edit " .. vim.fn.fnameescape(sc.path))
      vim.api.nvim_win_set_cursor(0, { sc.start_line, 0 })
    end,
  })
end

local function all_scenes(prj)
  local scenes = index.scenes(prj)
  for _, sc in ipairs(scenes) do
    if sc.words == nil then
      sc.words = index.scene_words(sc)
    end
  end
  table.sort(scenes, function(a, b)
    return a.start_line < b.start_line
  end)
  return scenes
end

-- Pick a predicate -> candidate value -> matching scene.
M.pick = function(prj)
  prj = prj or project.current()
  if not prj then
    not_in_project()
    return
  end
  local preds = config.get().collections.predicates or {}
  local labels = {
    pov = "POV",
    location = "Location",
    status = "Status",
    planning = "Planning",
    unfinished = "Unfinished scenes",
    tagged = "Tagged",
  }
  local entries = {}
  for _, p in ipairs(preds) do
    entries[#entries + 1] = { value = p, display = labels[p] or p }
  end
  pickers.pick_list(entries, {
    prompt_title = "Storyteller · collection",
    on_select = function(name)
      M.run(name, prj)
    end,
  })
end

-- Run a single predicate against a project.
M.run = function(name, prj)
  prj = prj or project.current()
  if not prj then
    not_in_project()
    return
  end
  local scenes = all_scenes(prj)

  if name == "unfinished" then
    local matches = {}
    for _, sc in ipairs(scenes) do
      if scene_unfinished(sc) then
        table.insert(matches, sc)
      end
    end
    M.present(matches, "Unfinished scenes")
    return
  end

  local candidates = candidates_for(name, scenes)
  if #candidates == 0 then
    vim.notify(("[storyteller] No %s values found."):format(name), vim.log.levels.INFO)
    return
  end
  local entries = {}
  for _, c in ipairs(candidates) do
    entries[#entries + 1] = { value = c, display = tostring(c) }
  end
  pickers.pick_list(entries, {
    prompt_title = ("Storyteller · filter by %s"):format(name),
    on_select = function(val)
      local matches = {}
      for _, sc in ipairs(scenes) do
        local hit
        if name == "tagged" then
          hit = scene_has_tag(sc, val)
        else
          hit = tostring(scene_field(sc, name)) == val
        end
        if hit then
          table.insert(matches, sc)
        end
      end
      M.present(matches, ("%s = %s"):format(name, val))
    end,
  })
end

-- Add the scene under the cursor to a named saved collection.
M.collect = function(prj)
  prj = prj or project.current()
  if not prj then
    not_in_project()
    return
  end
  local file = vim.fn.expand("%:p")
  if file == "" then
    return
  end
  local line = vim.fn.line(".")
  local hit
  for _, sc in ipairs(all_scenes(prj)) do
    if sc.path == file and sc.start_line <= line and (sc.end_line or math.huge) >= line then
      hit = sc
      break
    end
  end
  if not hit then
    vim.notify("[storyteller] Cursor is not inside a scene.", vim.log.levels.WARN)
    return
  end
  local name = vim.fn.input("Collection name: ")
  name = name:gsub("^%s+", ""):gsub("%s+$", "")
  if name == "" then
    return
  end
  M.saved[name] = M.saved[name] or {}
  for _, s in ipairs(M.saved[name]) do
    if s.path == hit.path and s.start_line == hit.start_line then
      return
    end
  end
  table.insert(M.saved[name], {
    path = hit.path,
    title = hit.title or vim.fn.fnamemodify(hit.path, ":t:r"),
    start_line = hit.start_line,
    end_line = hit.end_line,
  })
  vim.notify(
    ("[storyteller] Added scene to '%s' (%d scene(s))."):format(name, #M.saved[name]),
    vim.log.levels.INFO
  )
end

-- Browse saved named collections like a filter; picking one picks a scene.
M.show = function()
  local names = {}
  for n in pairs(M.saved) do
    names[#names + 1] = n
  end
  if #names == 0 then
    vim.notify("[storyteller] No saved collections yet.", vim.log.levels.INFO)
    return
  end
  table.sort(names)
  local entries = {}
  for _, n in ipairs(names) do
    entries[#entries + 1] = { value = n, display = ("%s · %d scene(s)"):format(n, #M.saved[n]) }
  end
  pickers.pick_list(entries, {
    prompt_title = "Storyteller · saved collections",
    on_select = function(name)
      M.present_scenes(M.saved[name], name)
    end,
  })
end

-- Present saved scene references (a lighter variant that already has lines).
M.present_scenes = function(scenes, title)
  if #scenes == 0 then
    return
  end
  local entries = {}
  for _, s in ipairs(scenes) do
    entries[#entries + 1] = { value = s, display = ("%s [%s]"):format(s.title or s.path, vim.fn.fnamemodify(s.path, ":t:r")) }
  end
  pickers.pick_list(entries, {
    prompt_title = "Storyteller · " .. (title or "collection"),
    on_select = function(s)
      vim.cmd("edit " .. vim.fn.fnameescape(s.path))
      vim.api.nvim_win_set_cursor(0, { s.start_line, 0 })
    end,
  })
end

M.setup = function()
  command.register("CollectionAdd", function(_)
    M.collect()
  end, { desc = "Add the current scene to a saved collection", opts = { nargs = 0 } })

  command.register("Collections", function(_)
    M.show()
  end, { desc = "Browse saved collections like a filter", opts = { nargs = 0 } })
end

return M