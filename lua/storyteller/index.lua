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

-- mtime+size keyed line cache: repeated scans stat files instead of re-reading.
local lines_cache = {} -- path -> { sig, lines }

local function fsig(path)
  local st = vim.loop.fs_stat(path)
  if not st then
    return nil
  end
  return st.mtime.sec .. "." .. st.mtime.nsec .. ":" .. st.size
end

local function cached_lines(path)
  local sig = fsig(path)
  if not sig then
    return {}
  end
  local c = lines_cache[path]
  if c and c.sig == sig then
    return c.lines
  end
  local lines = vim.fn.readfile(path)
  lines_cache[path] = { sig = sig, lines = lines }
  return lines
end

-- rg if configured, else glob fallback. Returns absolute file paths.
local function list_md(dir)
  if not dir or vim.fn.isdirectory(dir) ~= 1 then
    return {}
  end
  local rg = config.bin("rg")
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
  local lines = cached_lines(path)
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
  -- Frontmatter status: `unused` shelves the whole chapter from compilation.
  info.status = doc and doc.meta.status or nil

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
-- before an em/en-dash or colon. Card fields read from either form —
-- `- **Key:** value` bullets or `### Key` heading sections (spec/metadata.md,
-- "Fields: bullets or headings") — into one case-insensitive map where the
-- first occurrence wins.
local function parse_reference(path)
  local lines = cached_lines(path)
  local title = nil
  local title_i = nil
  for i = 1, math.min(#lines, 16) do
    local h = lines[i]:match("^#+%s+(.*)$")
    if h then
      title = h
      title_i = i
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
  -- Unified field view: `### Key` sections ∪ `- **Key:**` bullets below the
  -- card's own title. First form seen for a key (case-insensitive) wins.
  local fields = {}
  local function add(key, value)
    local k = key:lower()
    if fields[k] == nil then
      fields[k] = { key = key, value = value }
    end
  end
  if title_i then
    local section_key, section_value = nil, {}
    local function flush()
      if section_key then
        add(section_key, vim.trim(table.concat(section_value, " ")))
      end
      section_key, section_value = nil, {}
    end
    for i = title_i + 1, #lines do
      local ln = lines[i]
      local head = ln:match("^#+%s+(.*)$")
      if head then
        flush()
        section_key, section_value = head, {}
      else
        local bullet_key, bullet_value = ln:match("^%-%s*%*%*([^*]+):%*%*%s*(.*)$")
        if bullet_key then
          flush()
          add(bullet_key, bullet_value)
        elseif section_key and ln ~= "" then
          section_value[#section_value + 1] = ln
        end
      end
    end
    flush()
  end
  return {
    path = path,
    title = title,
    name = name,
    names = names,
    meta = doc and doc.meta or {},
    fields = fields,
  }
end

-- --- Public API -------------------------------------------------------------

-- mtime-keyed caches so repeated scans (dashboard refresh, statusline, etc.)
-- stat files instead of re-reading and re-parsing them.
local chapter_cache = {} -- root -> { files, sigs, chapters }

-- Chapters in a project (lexical file order). Parsed chapters are cached per
-- root and invalidated when any listed file's mtime/size changes.
M.chapters = function(prj)
  prj = prj or project.current()
  if not prj then
    return {}
  end
  local files = list_md(prj.chapters)
  local sigs = {}
  for _, p in ipairs(files) do
    sigs[p] = fsig(p)
  end
  local c = chapter_cache[prj.root]
  if c and #c.files == #files then
    local same = true
    for i, p in ipairs(files) do
      if c.files[i] ~= p or c.sigs[p] ~= sigs[p] then
        same = false
        break
      end
    end
    if same then
      return c.chapters
    end
  end
  local out = {}
  for _, p in ipairs(files) do
    out[#out + 1] = parse_chapter(p)
  end
  chapter_cache[prj.root] = { files = files, sigs = sigs, chapters = out }
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
    elseif
      not in_fence
      and not line:match("^%s*#")
      and not line:match("^%s*-%s*%*%*[%a ]+%*%*:%s*")
    then
      for _ in line:gmatch("%S+") do
        count = count + 1
      end
    end
  end
  return count
end

M.count_prose = count_prose

M.scene_words = function(sc)
  local lines = cached_lines(sc.path)
  local block = sc.yaml or meta.scene_block(lines, sc.start_line, sc.end_line or #lines)
  return count_prose(lines, block.content_start or (sc.start_line + 1), sc.end_line or #lines)
end

M.chapter_words = function(ch)
  if ch.status == "unused" then
    return 0
  end
  local total = 0
  for _, sc in ipairs(ch.scenes) do
    -- Shelved (`unused`) scenes stay out of word totals, matching their
    -- exclusion from compilation.
    if (sc.meta and sc.meta.status) ~= "unused" then
      total = total + (sc.words or M.scene_words(sc))
    end
  end
  local lines = cached_lines(ch.path)
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

-- Reference cards by type. Any subfolder under references/ is a type (folder
-- name = type id), so custom codex categories work without configuration.
M.references = function(prj)
  prj = prj or project.current()
  local out = {}
  if not prj or vim.fn.isdirectory(prj.references) ~= 1 then
    return out
  end
  local subdirs = vim.fn.glob(prj.references .. "/*", false, true)
  for _, sub in ipairs(subdirs) do
    if vim.fn.isdirectory(sub) == 1 then
      local t = vim.fn.fnamemodify(sub, ":t")
      local cards = {}
      for _, p in ipairs(list_md(sub)) do
        cards[#cards + 1] = parse_reference(p)
      end
      out[t] = cards
    end
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

-- Scenes ordered by numeric story time when available. Free-form time keeps
-- manuscript order so the timeline never invents chronology.
--
-- With an axis name, rows become placements on that axis (schema v1.2): the
-- primary coordinate of scenes declared there (`timeline:`), plus every
-- `also:` placement addressed to it. Secondary rows share their scene and are
-- marked `timeline_secondary`.
M.timeline = function(prj, axis)
  axis = axis or "main"
  -- Ordinal ranks come from the axis card's `order:` sequence when declared.
  local ameta
  for _, a in ipairs(M.timeline_axes(prj)) do
    if a.name:lower() == axis:lower() then
      ameta = a
    end
  end
  local function rank_of(value)
    if not ameta or #ameta.order == 0 or value == nil then
      return nil
    end
    local s = tostring(value):lower()
    for i, o in ipairs(ameta.order) do
      if tostring(o):lower() == s then
        return i
      end
    end
    return nil
  end

  local out = {}
  local previous_numeric = nil
  for order, scene in ipairs(M.scenes(prj)) do
    local m = scene.meta or {}
    local declared = m.timeline and tostring(m.timeline) or nil
    local on_primary = (declared == nil and axis == "main")
      or (declared ~= nil and declared:lower() == axis:lower())
    if on_primary then
      local value = m.day or m.time
      local numeric = tonumber(value)
      scene.timeline_order = order
      scene.timeline_value = value
      scene.timeline_numeric = numeric
      scene.timeline_rank = rank_of(value)
      scene.timeline_secondary = false
      scene.timeline_regression = numeric and previous_numeric and numeric < previous_numeric
        or false
      if numeric then
        previous_numeric = numeric
      end
      out[#out + 1] = scene
    end
    for _, entry in ipairs(type(m.also) == "table" and m.also or { m.also }) do
      local text = entry and tostring(entry) or ""
      local ax = text:match("timeline:%s*([^,}]+)")
      local coord = text:match("at:%s*([^,}]+)")
        or text:match("day:%s*([^,}]+)")
        or text:match("time:%s*([^,}]+)")
      if ax and coord then
        ax = vim.trim(ax)
        if ax:lower() == axis:lower() then
          -- A shallow copy so per-row timeline fields don't leak between axes.
          local coord = vim.trim(coord)
          local row = setmetatable({
            timeline_order = order,
            timeline_value = coord,
            timeline_numeric = tonumber(coord),
            timeline_rank = rank_of(coord),
            timeline_secondary = true,
            timeline_regression = false,
            _label = nil,
          }, { __index = scene })
          out[#out + 1] = row
        end
      end
    end
  end
  table.sort(out, function(a, b)
    local ka = a.timeline_rank or a.timeline_numeric
    local kb = b.timeline_rank or b.timeline_numeric
    if ka and kb and ka ~= kb then
      return ka < kb
    end
    if ka and not kb then
      return true
    end
    if kb and not ka then
      return false
    end
    return a.timeline_order < b.timeline_order
  end)
  return out
end

--- Timeline card metadata: `references/timelines/<name>.md` frontmatter
--- carries `order:` (ordinal sequence) and `unit:` (display label).
local function load_axis_meta(prj, name)
  local dir = prj.root .. "/references/timelines"
  for _, p in ipairs(list_md(dir)) do
    local stem = vim.fn.fnamemodify(p, ":t:r")
    if stem:lower() == name:lower() then
      local doc = meta.chapter(p)
      local d = doc and doc.meta or {}
      return {
        name = name,
        order = type(d.order) == "table" and d.order or {},
        unit = d.unit and tostring(d.unit) or nil,
      }
    end
  end
  return { name = name, order = {}, unit = nil }
end

-- Declared axes for the project: implicit main first, then every timeline
-- card (sorted). Each entry: { name, order = {...}, unit }.
M.timeline_axes = function(prj)
  prj = prj or project.current()
  local out = { { name = "main", order = {}, unit = nil } }
  local seen = { main = true }
  local extra = {}
  local dir = prj and prj.root and (prj.root .. "/references/timelines") or nil
  for _, p in ipairs(dir and list_md(dir) or {}) do
    local stem = vim.fn.fnamemodify(p, ":t:r")
    if not seen[stem:lower()] then
      seen[stem:lower()] = true
      extra[#extra + 1] = stem
    end
  end
  table.sort(extra)
  for _, name in ipairs(extra) do
    out[#out + 1] = load_axis_meta(prj, name)
  end
  return out
end

-- Group setup/payoff keys into plot threads and retain the scenes that carry
-- each side. This is derived data; the scene YAML remains authoritative.
M.plot_threads = function(prj)
  local threads = {}
  local function add(value, side, scene)
    if type(value) == "table" then
      for _, item in ipairs(value) do
        add(item, side, scene)
      end
    elseif value and tostring(value) ~= "" then
      local key = tostring(value)
      threads[key] = threads[key] or { key = key, setup = {}, payoff = {} }
      threads[key][side][#threads[key][side] + 1] = scene
    end
  end
  for _, scene in ipairs(M.scenes(prj)) do
    add(scene.meta and scene.meta.setup, "setup", scene)
    add(scene.meta and scene.meta.payoff, "payoff", scene)
  end
  local out = {}
  for _, thread in pairs(threads) do
    thread.state = #thread.setup > 0 and #thread.payoff > 0 and "complete"
      or (#thread.setup > 0 and "needs payoff" or "needs setup")
    out[#out + 1] = thread
  end
  table.sort(out, function(a, b)
    return a.key < b.key
  end)
  return out
end

-- Plotline lanes (schema v1.2): one lane per `references/plotlines/*.md`
-- track card, its declared `stages:` sequence, the scenes attached to it in
-- manuscript order with per-lane stage regressions flagged, and declared
-- stages no attached scene has reached. Mirrors the LSP `storyteller.plotlines`
-- shape. Scenes attach via a case-insensitive name match on `plotlines:`.
M.plotlines = function(prj)
  prj = prj or project.current()
  local lanes = {}
  local known = {}
  local dir = prj and prj.root and (prj.root .. "/references/plotlines") or nil
  for _, p in ipairs(dir and list_md(dir) or {}) do
    local doc = meta.chapter(p)
    local d = doc and doc.meta or {}
    local stages = type(d.stages) == "table" and d.stages or {}
    local ref = parse_reference(p)
    local lane = {
      name = ref.name,
      file = p,
      arc_of = d.arc_of and tostring(d.arc_of) or nil,
      stages = vim.tbl_map(tostring, stages),
      scenes = {},
      uncovered = {},
    }
    -- Every alias attaches: a card titled "The Telemachy" still matches
    -- scenes that reference plain "Telemachy".
    lane.aliases = { lane.name:lower() }
    for _, alias in ipairs(ref.names or {}) do
      local k = tostring(alias):lower()
      if not vim.list_contains(lane.aliases, k) then
        lane.aliases[#lane.aliases + 1] = k
      end
    end
    for _, alias in ipairs(lane.aliases) do
      known[alias] = true
    end
    lanes[#lanes + 1] = lane
  end
  table.sort(lanes, function(a, b)
    return a.name:lower() < b.name:lower()
  end)

  local stage_rank = function(lane, stage)
    if not stage then
      return nil
    end
    for i, s in ipairs(lane.stages) do
      if s:lower() == tostring(stage):lower() then
        return i
      end
    end
    return nil
  end

  -- Attach scenes in manuscript order; flag within-lane stage drops.
  for _, scene in ipairs(M.scenes(prj)) do
    local m = scene.meta or {}
    local names = type(m.plotlines) == "table" and m.plotlines or { m.plotlines }
    for _, raw in ipairs(names) do
      if raw and tostring(raw) ~= "" then
        local key = tostring(raw):lower()
        if not known[key] then
          scene.orphan_plotline = scene.orphan_plotline or tostring(raw)
        end
        for _, lane in ipairs(lanes) do
          if vim.list_contains(lane.aliases, key) then
            local rank = stage_rank(lane, m.stage)
            local previous = lane.scenes[#lane.scenes]
            local regression = previous ~= nil
              and previous.rank ~= nil
              and rank ~= nil
              and rank < previous.rank
            lane.scenes[#lane.scenes + 1] = {
              scene = scene,
              stage = m.stage and tostring(m.stage) or nil,
              rank = rank,
              regression = regression,
            }
          end
        end
      end
    end
  end

  -- Declared stages no attached scene has reached.
  for _, lane in ipairs(lanes) do
    local reached = {}
    for _, entry in ipairs(lane.scenes) do
      if entry.rank then
        reached[entry.rank] = true
      end
    end
    for i, stage in ipairs(lane.stages) do
      if not reached[i] then
        lane.uncovered[#lane.uncovered + 1] = stage
      end
    end
  end
  return lanes
end

-- A calm review list for scenes that deserve a second look.
M.story_health = function(prj)
  local findings = {}
  for _, scene in ipairs(M.scenes(prj)) do
    local m = scene.meta or {}
    if m.goal and not m.conflict then
      findings[#findings + 1] = { kind = "beat", label = "Goal without conflict", scene = scene }
    elseif m.conflict and not m.outcome then
      findings[#findings + 1] = { kind = "beat", label = "Conflict without outcome", scene = scene }
    end
    local target = tonumber(m.target)
    if target and scene.words and scene.words > target then
      findings[#findings + 1] = { kind = "length", label = "Over scene target", scene = scene }
    end
    if not m.time and not m.day then
      findings[#findings + 1] = { kind = "timeline", label = "No story time", scene = scene }
    end
  end
  for _, thread in ipairs(M.plot_threads(prj)) do
    if thread.state ~= "complete" then
      findings[#findings + 1] =
        { kind = "thread", label = thread.key .. " · " .. thread.state, thread = thread }
    end
  end
  -- Schema v1.2 plotline gates (docs/rework-plan.md H2).
  local lanes = M.plotlines(prj)
  for _, lane in ipairs(lanes) do
    for _, entry in ipairs(lane.scenes) do
      if entry.regression then
        findings[#findings + 1] = {
          kind = "stage_regression",
          label = ("%s · stage back to %s"):format(lane.name, tostring(entry.stage)),
          scene = entry.scene,
        }
      end
    end
    for _, stage in ipairs(lane.uncovered) do
      findings[#findings + 1] = {
        kind = "uncovered_stage",
        label = ("%s · no scene at %s"):format(lane.name, stage),
        lane = lane,
      }
    end
  end
  for _, scene in ipairs(M.scenes(prj)) do
    if scene.orphan_plotline then
      findings[#findings + 1] = {
        kind = "orphan_plotline",
        label = ("no track card for %q"):format(scene.orphan_plotline),
        scene = scene,
      }
    end
  end
  return findings
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
    if
      scene.path == file
      and scene.start_line <= cursor
      and cursor <= (scene.end_line or math.huge)
    then
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
M.cached_lines = cached_lines

-- Drop all caches (used by tests and by schema/config reloads).
M.invalidate = function()
  lines_cache = {}
  chapter_cache = {}
end

return M
