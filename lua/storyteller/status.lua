-- storyteller.status
-- Pure data for statusline/lualine consumption.
--   status.context(bufnr) -> { scene_words, chapter_words, target, pct }
--   status.render()       -> short formatted string for a statusline component
--
-- Reads only the current buffer (no project-wide scan) so it stays cheap for
-- the statusline's frequent ticks.

local M = {}
local project = require("storyteller.project")
local index = require("storyteller.index")
local meta = require("storyteller.meta")

local function parse_target(lines)
  if lines[1] == "---" then
    for i = 2, #lines do
      local t = lines[i]:match("^target:%s*(%d+)")
      if t then
        return tonumber(t)
      end
      if lines[i] == "---" then
        break
      end
    end
  end
  for _, ln in ipairs(lines) do
    local t = ln:match("^%s*[#>*]%s*Target:%s*(%d+)")
    if t then
      return tonumber(t)
    end
  end
  return nil
end

M.context = function(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local target = parse_target(lines)

  local prj = project.current()
  local active_scene = prj and index.current_scene(prj) or nil
  if active_scene then
    target = meta.field(active_scene, "target", target)
  end

  local scene_words = active_scene and index.scene_words(active_scene) or 0
  if not active_scene then
    local cursor = vim.api.nvim_win_get_cursor(0)[1]
    local start_line, end_line
    for i = 1, #lines do
      if lines[i]:match("^##%s+") then
        if start_line == nil then
          start_line = i
        end
        if i > cursor then
          end_line = i - 1
          break
        end
        start_line = i
      end
    end
    if start_line then
      end_line = end_line or #lines
      local body = table.concat(vim.list_slice(lines, start_line, end_line), " ")
      for _ in body:gmatch("%S+") do
        scene_words = scene_words + 1
      end
    end
  end

  -- Prose-only count (frontmatter, scene YAML, and metadata bullets excluded)
  -- so the statusline agrees with outline/tracking numbers.
  local start = 1
  if lines[1] == "---" then
    for i = 2, #lines do
      if lines[i] == "---" then
        start = i + 1
        break
      end
    end
  end
  local cw = index.count_prose(lines, start, #lines)
  return {
    scene_words = scene_words,
    chapter_words = cw,
    target = target,
    pct = target and target > 0 and math.floor(cw / target * 100) or nil,
  }
end

M.render = function()
  local c = M.context()
  if not c then
    return ""
  end
  local parts = {}
  if c.scene_words > 0 then
    parts[#parts + 1] = ("⚑ %s"):format(c.scene_words)
  end
  if c.target then
    parts[#parts + 1] = ("%s/%s (%s%%)"):format(c.chapter_words, c.target, c.pct or 0)
  else
    parts[#parts + 1] = tostring(c.chapter_words)
  end
  return table.concat(parts, " ")
end

return M
