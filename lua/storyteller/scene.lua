-- storyteller.scene
-- Scene-local YAML blocks and stable identifiers. A block is optional and
-- remains ordinary Markdown immediately below a `## Scene` heading:
--
-- ```yaml
-- storyteller: scene
-- id: 1a2b3c4d
-- status: revision
-- pov: Odysseus
-- tags:
--   - act-1
-- ```

local M = {}

local ORDER = {
  "id", "status", "planning", "pov", "location", "time",
  "goal", "conflict", "outcome", "beat", "target", "tags",
  "chars", "locs", "items", "orgs", "ignore",
}

local function trim(value)
  return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function scalar(value)
  value = trim(value)
  if value == "true" then
    return true
  elseif value == "false" then
    return false
  end
  local number = tonumber(value)
  if number then
    return number
  end
  return value:gsub("^[\"']", ""):gsub("[\"']$", "")
end

local function parse(lines, start_line, end_line)
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
  if not close or trim(lines[first + 1] or "") ~= "storyteller: scene" then
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
          values[#values + 1] = scalar(item)
          next_line = next_line + 1
        end
        meta[key] = values
        line = next_line
      else
        meta[key] = scalar(value)
        line = line + 1
      end
    else
      line = line + 1
    end
  end
  return {
    meta = meta,
    yaml_start = first,
    yaml_end = close,
    content_start = close + 1,
  }
end

local function render(meta)
  local lines = { "```yaml", "storyteller: scene" }
  local written = {}
  local function add(key, value)
    if value == nil then
      return
    end
    if type(value) == "table" then
      lines[#lines + 1] = key .. ":"
      for _, item in ipairs(value) do
        lines[#lines + 1] = "  - " .. tostring(item)
      end
    else
      lines[#lines + 1] = key .. ": " .. tostring(value)
    end
    written[key] = true
  end
  for _, key in ipairs(ORDER) do
    add(key, meta[key])
  end
  for key, value in pairs(meta) do
    if not written[key] then
      add(key, value)
    end
  end
  lines[#lines + 1] = "```"
  return lines
end

local function source_lines(path)
  return vim.fn.readfile(path)
end

local function sync_clean_buffer(path, lines)
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_get_name(bufnr) == path and not vim.bo[bufnr].modified then
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
      vim.bo[bufnr].modified = false
    end
  end
end

M.parse = parse
M.render = render

M.from_index = function(scene, lines)
  lines = lines or source_lines(scene.path)
  local block = parse(lines, scene.start_line, scene.end_line or #lines)
  local meta = vim.tbl_extend("force", {}, scene.inline or scene.meta or {}, block.meta)
  return vim.tbl_extend("force", block, { meta = meta })
end

M.ensure_id = function(scene)
  local lines = source_lines(scene.path)
  local block = parse(lines, scene.start_line, scene.end_line or #lines)
  if block.meta.id then
    return block.meta.id
  end
  local seed = table.concat({ scene.path, scene.title or "", tostring(vim.uv.hrtime()) }, ":")
  local id = vim.fn.sha256(seed):sub(1, 12)
  block.meta.id = id
  local replacement = render(block.meta)
  local first = block.yaml_start or (scene.start_line + 1)
  local last = block.yaml_end or scene.start_line
  for i = last, first, -1 do
    table.remove(lines, i)
  end
  for i = #replacement, 1, -1 do
    table.insert(lines, first, replacement[i])
  end
  vim.fn.writefile(lines, scene.path)
  sync_clean_buffer(scene.path, lines)
  return id
end

M.update = function(scene, patch)
  local lines = source_lines(scene.path)
  local block = parse(lines, scene.start_line, scene.end_line or #lines)
  local meta = block.meta
  for key, value in pairs(patch) do
    meta[key] = value
  end
  if not meta.id then
    meta.id = vim.fn.sha256(table.concat({ scene.path, scene.title or "", tostring(vim.uv.hrtime()) }, ":")):sub(1, 12)
  end
  local replacement = render(meta)
  local first = block.yaml_start or (scene.start_line + 1)
  local last = block.yaml_end or scene.start_line
  for i = last, first, -1 do
    table.remove(lines, i)
  end
  for i = #replacement, 1, -1 do
    table.insert(lines, first, replacement[i])
  end
  vim.fn.writefile(lines, scene.path)
  sync_clean_buffer(scene.path, lines)
  return meta
end

M.current = function(prj)
  local index = require("storyteller.index")
  local file = vim.api.nvim_buf_get_name(0)
  local cursor = vim.api.nvim_win_get_cursor(0)[1]
  for _, scene in ipairs(index.scenes(prj)) do
    if scene.path == file and scene.start_line <= cursor and cursor <= (scene.end_line or math.huge) then
      return scene
    end
  end
  return nil
end

return M
