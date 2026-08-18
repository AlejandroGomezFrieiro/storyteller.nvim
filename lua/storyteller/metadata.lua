-- storyteller.metadata
-- Minimal YAML-frontmatter read/merge/write. No external YAML dependency.
--
-- Supported (the subset the plugin manages):
--   * scalars/booleans/numbers: `key: value`
--   * lists:                    `key:` + indented `- item`
--   * comments (`# ...`) at top level: preserved verbatim
--
-- Contract (frozen for parallel subagents):
--   metadata.read(path)            -> { meta, has_block } or nil
--   metadata.write(path, meta)      -> rewrites frontmatter preserving body
--   metadata.load(path, key)        -> typed value or nil
--   metadata.set(path, key, value)  -> shallow set a scalar
--   metadata.push(path, key, item)  -> append to a list (dedupe)
--   metadata.remove(path, key, item)-> remove from a list (or the key)
--   metadata.path_from_buf(bufnr)   -> buf path ("" -> nil)
--
-- Frontmatter keys the plugin manages (order stable for regeneration).
local ORDER = {
  "type",
  "pov",
  "location",
  "status",
  "planning",
  "target",
  "chars",
  "locs",
  "items",
  "orgs",
  "ignore",
  "tags",
  "aliases",
  "names",
}

local M = {}

local function strip(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Parse a scalar string into a typed Lua value.
local function parse_scalar(s)
  s = strip(s)
  if s == "" then
    return nil
  end
  if s == "true" then
    return true
  end
  if s == "false" then
    return false
  end
  local n = tonumber(s)
  if n then
    return n
  end
  -- strip surrounding quotes
  s = s:gsub("^[\"']", ""):gsub("[\"']$", "")
  return s
end

-- Parse frontmatter text (between ^--- and ^---) into a meta table.
-- Returns { meta = table, body_start = line_index_after_block, ok = bool }
local function parse_block(lines)
  local meta = {}
  if #lines < 1 or strip(lines[1]) ~= "---" then
    return nil
  end
  -- find closing delimiter
  local close = nil
  for i = 2, #lines do
    if strip(lines[i]) == "---" then
      close = i
      break
    end
  end
  if not close then
    return nil
  end

  local i = 2
  while i < close do
    local line = lines[i]
    if line:match("^%s*$") or line:match("^%s*#") then
      i = i + 1 -- blank / comment
    else
      local key, rest = line:match("^%s*([%w_]+)%s*:%s*(.-)%s*$")
      if key then
        if rest == "" then
          -- list block: collect following `- item` lines
          local list = {}
          local j = i + 1
          while j < close do
            local item = lines[j]:match("^%s*%-%s*(.+)$")
            if item then
              table.insert(list, parse_scalar(item))
              j = j + 1
            else
              break
            end
          end
          meta[key] = #list > 0 and list or {}
          i = j
        else
          meta[key] = parse_scalar(rest)
          i = i + 1
        end
      else
        i = i + 1
      end
    end
  end

  return {
    meta = meta,
    body_start = close + 1,
    ok = true,
  }
end

-- Encode a meta table into frontmatter lines (ordered by ORDER, then extras).
local function encode(meta)
  local lines = { "---" }
  local written = {}
  local function emit(key, value)
    if value == nil then
      return
    end
    if type(value) == "table" then
      lines[#lines + 1] = key .. ":"
      if #value > 0 then
        for _, v in ipairs(value) do
          lines[#lines + 1] = ("  - %s"):format(v)
        end
      end
    elseif type(value) == "boolean" then
      lines[#lines + 1] = ("%s: %s"):format(key, tostring(value))
    else
      lines[#lines + 1] = ("%s: %s"):format(key, tostring(value))
    end
    written[key] = true
  end

  for _, k in ipairs(ORDER) do
    if meta[k] ~= nil then
      emit(k, meta[k])
      written[k] = true
    end
  end
  -- any keys not in ORDER (preserve order of insertion)
  for k, v in pairs(meta) do
    if not written[k] then
      emit(k, v)
    end
  end
  lines[#lines + 1] = "---"
  return lines
end

-- --- File ops ---------------------------------------------------------------

local function read_lines(path)
  if path == "" or not vim.loop.fs_stat(path) then
    return nil
  end
  return vim.fn.readfile(path)
end

-- Read metadata for a file. Returns `nil` if no frontmatter.
--   * parses the block
--   * keeps the raw body (everything after the closing ---)
--   returns { path=path, meta=table, body=table(lines), had_block=bool }
local function read(path)
  local lines = read_lines(path)
  if not lines then
    return nil
  end
  local parsed = parse_block(lines)
  if not parsed then
    return { path = path, meta = {}, body = lines, had_block = false }
  end
  return {
    path = path,
    meta = parsed.meta,
    body = vim.list_slice(lines, parsed.body_start),
    had_block = true,
  }
end

-- Regenerate the file from a `read` result (merged meta). Reuses body.
local function write(doc)
  local new_lines = {}
  if not vim.deep_equal(doc.meta, {}) or doc.had_block then
    vim.list_extend(new_lines, encode(doc.meta))
  end
  vim.list_extend(new_lines, doc.body)
  vim.fn.writefile(new_lines, doc.path)
end

-- Apply a mutator to a file's meta and persist. Returns the meta.
local function mutate(path, fn)
  local doc = read(path)
  if not doc then
    return nil
  end
  fn(doc.meta)
  doc.meta = doc.meta or {}
  write(doc)
  return doc.meta
end

-- --- Public API -------------------------------------------------------------

M.read = read
M.parse_block = parse_block
M.encode = encode
M.write = write

M.path_from_buf = function(bufnr)
  return vim.api.nvim_buf_get_name(bufnr)
end

M.load = function(path, key)
  local doc = read(path)
  if not doc then
    return nil
  end
  return doc.meta[key]
end

M.set = function(path, key, value)
  return mutate(path, function(meta)
    meta[key] = value
  end)
end

-- Append to a list field, deduplicated, ignoring case-distinct dupes loosely.
M.push = function(path, key, item)
  return mutate(path, function(meta)
    local list = meta[key]
    if not list then
      list = {}
      meta[key] = list
    end
    if type(list) ~= "table" then
      list = {}
      meta[key] = list
    end
    local norm = (item or ""):lower()
    for _, v in ipairs(list) do
      if tostring(v):lower() == norm then
        return
      end
    end
    table.insert(list, item)
  end)
end

M.remove = function(path, key, item)
  return mutate(path, function(meta)
    local list = meta[key]
    if type(list) ~= "table" then
      if item == nil then
        meta[key] = nil
      end
      return
    end
    if item == nil then
      meta[key] = nil
      return
    end
    local norm = (item or ""):lower()
    local out = {}
    for _, v in ipairs(list) do
      if tostring(v):lower() ~= norm then
        table.insert(out, v)
      end
    end
    meta[key] = out
  end)
end

return M