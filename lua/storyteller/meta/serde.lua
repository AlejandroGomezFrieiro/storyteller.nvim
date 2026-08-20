-- storyteller.meta.serde
-- Minimal YAML-subset (de)serialization for Storyteller metadata.
--
-- Handles the subset the plugin manages:
--   * scalars/booleans/numbers: `key: value`
--   * lists:                    `key:` + indented `- item`
--   * scene YAML blocks:        ```yaml / storyteller: scene / ... / ```
--
-- Comments and unsupported YAML lines are preserved verbatim on mutation so we
-- never discard a user's hand-written frontmatter.

local schema = require("storyteller.schema")

local M = {}

local function strip(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Parse a scalar string into a typed Lua value.
function M.scalar(s)
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
  return s:gsub("^[\"']", ""):gsub("[\"']$", "")
end

-- Parse a scalar or an inline YAML flow array (`key: [a, b, c]`). Returns a
-- list for flow arrays and a scalar otherwise.
local function parse_value(rest)
  rest = strip(rest)
  if rest:match("^%[.-%]$") then
    local inner = rest:match("^%[(.*)%]$")
    local list = {}
    for item in inner:gmatch("[^,%]]+") do
      item = strip(item)
      if item ~= "" then
        list[#list + 1] = M.scalar(item)
      end
    end
    return list
  end
  return M.scalar(rest)
end

-- Parse a frontmatter block (between ^--- and ^---).
-- Returns { meta = table, close = int, body_start = int } or nil.
function M.parse_frontmatter(lines)
  if #lines < 1 or strip(lines[1]) ~= "---" then
    return nil
  end
  local close
  for i = 2, #lines do
    if strip(lines[i]) == "---" then
      close = i
      break
    end
  end
  if not close then
    return nil
  end

  local meta = {}
  local i = 2
  while i < close do
    local line = lines[i]
    if line:match("^%s*$") or line:match("^%s*#") then
      i = i + 1
    else
      local key, rest = line:match("^%s*([%w_]+)%s*:%s*(.-)%s*$")
      if key then
        if rest == "" then
          local list = {}
          local j = i + 1
          while j < close do
            local item = lines[j]:match("^%s*%-%s*(.+)$")
            if item then
              list[#list + 1] = M.scalar(item)
              j = j + 1
            else
              break
            end
          end
          meta[key] = list
          i = j
        else
          meta[key] = parse_value(rest)
          i = i + 1
        end
      else
        i = i + 1
      end
    end
  end

  return { meta = meta, close = close, body_start = close + 1 }
end

-- Encode a meta table into `key: value` lines using `order` for stability.
function M.encode_map(meta, order)
  local lines = {}
  local written = {}

  local function emit(key, value)
    if value == nil then
      return
    end
    if type(value) == "table" then
      lines[#lines + 1] = key .. ":"
      for _, item in ipairs(value) do
        lines[#lines + 1] = "  - " .. tostring(item)
      end
    elseif type(value) == "boolean" then
      lines[#lines + 1] = key .. ": " .. tostring(value)
    else
      lines[#lines + 1] = key .. ": " .. tostring(value)
    end
    written[key] = true
  end

  for _, k in ipairs(order) do
    if meta[k] ~= nil then
      emit(k, meta[k])
    end
  end
  for k, v in pairs(meta) do
    if not written[k] then
      emit(k, v)
    end
  end
  return lines
end

-- Encode a meta table into a full frontmatter block (--- ... ---).
function M.encode_frontmatter(meta)
  local lines = { "---" }
  vim.list_extend(lines, M.encode_map(meta, schema.chapter_fields))
  lines[#lines + 1] = "---"
  return lines
end

-- Encode a meta table into a scene YAML block (```yaml storyteller: scene ... ```).
function M.encode_scene(meta)
  local lines = { "```yaml", schema.scene_sentinel }
  vim.list_extend(lines, M.encode_map(meta, schema.scene_fields))
  lines[#lines + 1] = "```"
  return lines
end

-- Parse a scene YAML block that begins right after a `## ` heading.
-- `lines` is the whole file; `start_line`/`end_line` bound the scene.
-- Returns { meta = {}, content_start = int, [yaml_start], [yaml_end] }.
function M.parse_scene_block(lines, start_line, end_line)
  local first = start_line + 1
  while first <= end_line and lines[first]:match("^%s*$") do
    first = first + 1
  end
  if lines[first] ~= "```yaml" then
    return { meta = {}, content_start = start_line + 1 }
  end
  local close
  for line = first + 1, end_line do
    if lines[line] == "```" then
      close = line
      break
    end
  end
  if not close or strip(lines[first + 1] or "") ~= schema.scene_sentinel then
    return { meta = {}, content_start = start_line + 1 }
  end

  local meta = {}
  local line = first + 2
  while line < close do
    local key, value = lines[line]:match("^([%w_]+):%s*(.-)%s*$")
    if key then
      if value == "" then
        local values = {}
        local next_line = line + 1
        while next_line < close do
          local item = lines[next_line]:match("^%s*%-%s*(.+)$")
          if not item then
            break
          end
          values[#values + 1] = M.scalar(item)
          next_line = next_line + 1
        end
        meta[key] = values
        line = next_line
      else
        meta[key] = parse_value(value)
        line = line + 1
      end
    else
      line = line + 1
    end
  end

  return { meta = meta, yaml_start = first, yaml_end = close, content_start = close + 1 }
end

-- Parse a bare `key: value` map (no delimiters) over a line range. Used by the
-- metadata form to read an edited field list back.
function M.parse_map(lines, start, stop)
  start = start or 1
  stop = stop or #lines
  local meta = {}
  local i = start
  while i <= stop do
    local line = lines[i]
    if line:match("^%s*$") or line:match("^%s*#") then
      i = i + 1
    else
      local key, rest = line:match("^%s*([%w_]+)%s*:%s*(.-)%s*$")
      if key then
        if rest == "" then
          local list = {}
          local j = i + 1
          while j <= stop do
            local item = lines[j]:match("^%s*%-%s*(.+)$")
            if item then
              list[#list + 1] = M.scalar(item)
              j = j + 1
            else
              break
            end
          end
          meta[key] = list
          i = j
        else
          meta[key] = parse_value(rest)
          i = i + 1
        end
      else
        i = i + 1
      end
    end
  end
  return meta
end

-- Parse an inline `- **Key:** value` bullet. Returns key, value.
function M.parse_inline(line)
  return line:match("^%s*%-%s*%*%*%s*([A-Za-z]+)%s*:%s*%*%*%s*(.*)$")
end

-- Emit an inline `- **Key:** value` bullet.
function M.encode_inline(key, value)
  return ("- **%s:** %s"):format(key:gsub("^%l", string.upper), tostring(value))
end

-- Preserve raw YAML/comments and rewrite only the fields that changed.
-- `raw` is the frontmatter block lines including delimiters.
function M.patch_frontmatter(raw, before, after)
  local changed = {}
  for key, value in pairs(after) do
    if not vim.deep_equal(before[key], value) then
      changed[key] = true
    end
  end
  for key in pairs(before) do
    if after[key] == nil then
      changed[key] = true
    end
  end
  if vim.tbl_isempty(changed) then
    return raw
  end

  local lines = { "---" }
  local i = 2
  local close = #raw
  while i < close do
    local line = raw[i]
    local key = line:match("^%s*([%w_]+)%s*:")
    if key and changed[key] then
      i = i + 1
      while i < close and raw[i]:match("^%s*%-%s+") do
        i = i + 1
      end
    else
      lines[#lines + 1] = line
      i = i + 1
    end
  end

  vim.list_extend(lines, M.encode_map(after, schema.chapter_fields))
  lines[#lines + 1] = "---"
  return lines
end

return M
