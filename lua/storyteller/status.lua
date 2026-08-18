-- storyteller.status
-- Pure data for statusline/lualine consumption (Phase 1).
--   status.context(bufnr) -> { scene_words, chapter_words, target, pct, scene_title }
--   status.render()       -> short formatted string for a statusline component
--
-- Reading only the *current buffer* (no disk I/O) so it's cheap enough for
-- the statusline's frequent ticks.

local M = {}

local function parse_target(lines)
  -- 1. frontmatter `target: 5000`
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
  -- 2. `# Target: N` or `> Target: N`
  for _, ln in ipairs(lines) do
    local t = ln:match("^%s*[#>*]%s*Target:%s*(%d+)")
    if t then
      return tonumber(t)
    end
  end
  return nil
end

-- Full chapter word count for the buffer (all prose lines).

M.context = function(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local target = parse_target(lines)

  -- current scene = word count from the nearest preceding `## ` heading
  local cursor = vim.api.nvim_win_get_cursor(0)[1] -- 1-based
  local scene_words = 0
  local start_line = nil
  local end_line = nil
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

  local cw = vim.fn.wordcount().words
  return {
    scene_words = scene_words,
    chapter_words = cw,
    target = target,
    pct = target and target > 0 and math.floor(cw / target * 100) or nil,
  }
end

-- Short, human string for a statusline slot. e.g. `·wokay` -> `1.2k/5k (24%)`
M.render = function()
  local c = M.context()
  if not c then
    return ""
  end
  local parts = {}
  if c.scene_words > 0 then
    table.insert(parts, ("⚑ %s"):format(c.scene_words))
  end
  if c.target then
    table.insert(parts, ("%s/%s (%s%%)"):format(c.chapter_words, c.target, c.pct or 0))
  else
    table.insert(parts, tostring(c.chapter_words))
  end
  return table.concat(parts, " ")
end

return M