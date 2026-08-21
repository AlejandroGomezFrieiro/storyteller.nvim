-- storyteller.schema
-- Single source of truth for Storyteller's metadata vocabulary, loaded at
-- runtime from three layers (embedded defaults < project file < client), merged
-- with a recipe that mirrors the reference implementation exactly.
--
-- The DEFAULTS are loaded from the bundled canonical schema.json so the plugin
-- never drifts from the standard. The mirror test in tests/storyteller_spec.lua
-- asserts DEFAULTS ≡ the canonical schema on disk.

local M = {}

-- Loaded from the bundled canonical schema.json at module-require time.
-- The file is a committed copy of the storyteller standard repo's schema.
local schema_path = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h") .. "/schema.json"
local ok, DEFAULTS = pcall(vim.json.decode, table.concat(vim.fn.readfile(schema_path), "\n"))
if not ok or not DEFAULTS then
  vim.notify(
    "[storyteller] Failed to load bundled schema.json; schema vocabulary unavailable.",
    vim.log.levels.ERROR
  )
  DEFAULTS = {}
end

-- --- Merge recipe (mirrors server/src/schema.rs; keep in lockstep) ----------

local function is_array(t)
  local n = 0
  for _ in pairs(t) do
    n = n + 1
  end
  return n == #t
end

local function is_removal(v)
  return v == nil or v == vim.NIL or (type(v) == "table" and v.remove == true)
end

local function merge_values(base, over)
  if type(base) ~= "table" or type(over) ~= "table" or (is_array(base) and is_array(over)) then
    return over
  end
  local out = vim.deepcopy(base)
  for k, v in pairs(over) do
    if is_removal(v) then
      out[k] = nil
    else
      out[k] = merge_values(base[k], v)
    end
  end
  return out
end

-- Minimal layer that, merged over `base`, reproduces `merged`. Deleted map keys
-- are emitted as JSON null so a write → load round-trip is lossless.
local function diff(base, merged)
  if type(merged) ~= "table" then
    return merged
  end
  if is_array(merged) then
    return merged -- arrays replace wholesale
  end
  local out = {}
  for k, v in pairs(merged) do
    out[k] = (base[k] ~= nil) and diff(base[k], v) or v
  end
  for k in pairs(base) do
    if merged[k] == nil then
      out[k] = vim.NIL
    end
  end
  return out
end

-- Minimal TOML extraction for `.storyteller.toml`: find `schema = "path"` at
-- the top level or under `[storyteller]`. (Neovim ships no TOML parser.)
local function toml_schema(text)
  local section = nil
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    local sec = line:match("^%s*%[([^%]]+)%]%s*$")
    if sec then
      section = sec:gsub("%s+$", "")
    else
      local key, value = line:match("^%s*([%w_-]+)%s*=%s*(.+)$")
      if key and (section == nil or section == "storyteller") and key == "schema" then
        local v = value:gsub("%s+#.*$", ""):gsub("^%s*", ""):gsub("%s*$", "")
        v = v:match("^\"(.*)\"$") or v:match("^'(.*)'$") or v
        return v
      end
    end
  end
  return nil
end

local function find_schema_file(root)
  local candidates = {
    root .. "/.storyteller/schema.json",
    root .. "/storyteller.schema.json",
  }
  for _, p in ipairs(candidates) do
    if vim.loop.fs_stat(p) then
      return p
    end
  end
  local toml = root .. "/.storyteller.toml"
  if vim.loop.fs_stat(toml) then
    local ok, lines = pcall(vim.fn.readfile, toml)
    if ok then
      local path = toml_schema(table.concat(lines, "\n"))
      if type(path) == "string" then
        local abs = root .. "/" .. path
        if vim.loop.fs_stat(abs) then
          return abs
        end
      end
    end
  end
  return nil
end

-- --- Public API -------------------------------------------------------------

-- Sync the M.* tables from a merged schema (last-loaded root wins).
local function apply(merged)
  merged = merged or {}
  M.version = merged.version or "1.0.0"
  M.statuses = merged.statuses or {}
  M.status_next = merged.status_next or {}
  M.enums = merged.enums or {}
  M.scene_fields = merged.scene_fields or {}
  M.chapter_fields = merged.chapter_fields or {}
  M.scene_field_defs = merged.scene_field_defs or {}
  M.chapter_field_defs = merged.chapter_field_defs or {}
  M.list_fields = {}
  for _, f in ipairs(merged.list_fields or {}) do
    M.list_fields[f] = true
  end
  M.reference_types = merged.reference_types or {}
  M.scene_sentinel = merged.scene_sentinel or "storyteller: scene"
  M.diagnostics = merged.diagnostics or {}
end

local cache = {}

-- Load (and cache) the merged schema for a project root, then apply it.
function M.load(root)
  if not root or vim.loop.fs_stat(root) == nil then
    return M.dump()
  end
  if cache[root] then
    apply(cache[root])
    return cache[root]
  end
  local merged = vim.deepcopy(DEFAULTS)
  local path = find_schema_file(root)
  if path then
    local ok, lines = pcall(vim.fn.readfile, path)
    if ok then
      local ok2, data = pcall(vim.json.decode, table.concat(lines, "\n"))
      if ok2 and type(data) == "table" then
        merged = merge_values(merged, data)
      else
        vim.notify("[storyteller] Invalid schema at " .. path .. " (ignored).", vim.log.levels.WARN)
      end
    end
  end
  cache[root] = merged
  apply(merged)
  return merged
end

function M.invalidate(root)
  cache[root] = nil
end

-- The merged schema table (defaults + project), for writing / introspection.
function M.dump(root)
  return root and M.load(root) or vim.deepcopy(DEFAULTS)
end

-- Write the merged defaults+project schema to storyteller.schema.json.
function M.write(root)
  local merged = M.dump(root)
  local layer = diff(DEFAULTS, merged)
  local path = root .. "/storyteller.schema.json"
  vim.fn.writefile({ vim.json.encode(layer) }, path)
  return path
end

-- Diagnostics toggle; unknown keys default on (matches server/schema.rs).
M.flag = function(key)
  return M.diagnostics[key] == nil or M.diagnostics[key] == true
end

-- --- Field helpers (unchanged public surface) -------------------------------

M.type_field = function(dir)
  for _, t in pairs(M.reference_types) do
    if t.dir == dir then
      return t.field
    end
  end
  return dir
end

M.type_label = function(dir)
  for _, t in pairs(M.reference_types) do
    if t.dir == dir then
      return t.label
    end
  end
  return dir:gsub("^%l", string.upper):gsub("[_-]", " ")
end

M.type_body = function(dir)
  for _, t in pairs(M.reference_types) do
    if t.dir == dir then
      return t.body
    end
  end
  return { "Notes" }
end

M.type_dirs = function(prj_dirs)
  local out = {}
  local seen = {}
  for _, t in pairs(M.reference_types) do
    if not seen[t.dir] then
      seen[t.dir] = true
      out[#out + 1] = t.dir
    end
  end
  for _, d in ipairs(prj_dirs or {}) do
    if not seen[d] then
      seen[d] = true
      out[#out + 1] = d
    end
  end
  return out
end

M.is_list = function(key)
  return M.list_fields[key] == true
end

M.is_scene_field = function(key)
  return vim.tbl_contains(M.scene_fields, key)
end

M.is_chapter_field = function(key)
  return vim.tbl_contains(M.chapter_fields, key)
end

M.valid_status = function(s)
  return vim.tbl_contains(M.statuses, s or "")
end

M.next_status = function(s)
  return M.status_next[s] or M.statuses[1]
end

-- Seed the module tables from DEFAULTS so consumers (and the mirror test)
-- work without an explicit load().
apply(vim.deepcopy(DEFAULTS))

return M
