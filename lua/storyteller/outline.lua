-- storyteller.outline
-- Phase 1: live per-section word counts as extmark virtual text on each
-- heading, plus a project outline picker with target/progress data.
--
--   outline.attach(bufnr)   enable virtual word counts on a markdown buffer
--   outline.detach(bufnr)   remove them
--   outline.sections(bufnr) -> [{level, title, words, target}]
--   outline.pick(project)   fuzzy-pick a chapter/scene by title + words

local project = require("storyteller.project")
local pickers = require("storyteller.pickers")

local M = {}

local NS = {}
local attached = {}

local function has_ns(bufnr)
  return NS[bufnr] ~= nil
end

local function ensure_ns(bufnr)
  NS[bufnr] = NS[bufnr] or vim.api.nvim_create_namespace(("StoryOutline%d"):format(bufnr))
  return NS[bufnr]
end

-- Parse the current buffer into heading sections with word counts.
-- Respects a frontmatter block and leaves `_`/code fences out of counts.
M.sections = function(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local sections = {}
  local body_start = 0
  if lines[1] == "---" then
    for i = 2, #lines do
      if lines[i] == "---" then
        body_start = i
        break
      end
    end
  end

  local count, in_fence = 0, false
  local pending = nil -- { title, level, line }

  local function flush()
    if pending then
      table.insert(sections, {
        title = pending.title,
        level = pending.level,
        line = pending.line,
        words = count,
      })
    end
    count = 0
  end

  for i = body_start + 1, #lines do
    local ln = lines[i]
    if ln:match("^```") then
      local code = ln:match("^```")
      if code == "```" then -- toggles fence (pre #) 
        in_fence = not in_fence
      end
      if not in_fence then
        count = count + 1 -- the fence opener word
      end
    else
      local lvl = ln:match("^#%s+") and 1 or ln:match("^##%s+") and 2 or nil
      if lvl and not in_fence then
        flush()
        pending = { title = ln:gsub("^#+%s*", ""), level = lvl, line = i }
      elseif not in_fence then
        for _ in ln:gmatch("%S+") do
          count = count + 1
        end
      end
    end
  end
  flush()
  return sections
end

local function render_section(bufnr, s)
  local ns = ensure_ns(bufnr)
  local text = (" %d words"):format(s.words)
  vim.api.nvim_buf_set_extmark(bufnr, ns, s.line - 1, 0, {
    virt_text = { { text, "Comment" } },
    virt_text_pos = "eol",
    hl_mode = "combine",
  })
end

-- Refresh virtual counts for a buffer (called after edits, debounced).
M.refresh = function(bufnr)
  if not attached[bufnr] then
    return
  end
  local ns = NS[bufnr]
  if ns then
    vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  end
  for _, s in ipairs(M.sections(bufnr)) do
    if s.level <= 2 then
      render_section(bufnr, s)
    end
  end
end

M.attach = function(bufnr)
  if attached[bufnr] then
    return
  end
  attached[bufnr] = true
  ensure_ns(bufnr)
  M.refresh(bufnr)
end

M.detach = function(bufnr)
  if NS[bufnr] then
    vim.api.nvim_buf_clear_namespace(bufnr, NS[bufnr], 0, -1)
  end
  NS[bufnr] = nil
  attached[bufnr] = nil
end

-- Wire autocmds for a markdown buffer (debounced refresh).
local timers = {}
M.setup_buffer = function(bufnr)
  if not attached[bufnr] then
    M.attach(bufnr)
  end
  local group = vim.api.nvim_create_augroup(("StorytellerOutline%d"):format(bufnr), { clear = true })
  local function schedule()
    if timers[bufnr] then
      vim.fn.timer_stop(timers[bufnr])
    end
    timers[bufnr] = vim.fn.timer_start(250, function()
      pcall(function()
        M.refresh(bufnr)
      end)
    end)
  end
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "InsertLeave" }, {
    group = group,
    buffer = bufnr,
    callback = schedule,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    buffer = bufnr,
    callback = function()
      M.detach(bufnr)
    end,
  })
end

M.is_attached = function(bufnr)
  return attached[bufnr] == true
end

-- Project outline picker: chapters with words, target, progress bar.
M.pick = function(prj)
  prj = prj or project.current()
  if not prj then
    return
  end
  local index = require("storyteller.index")
  local chapters = index.chapters(prj)
  local entries = {}
  for _, ch in ipairs(chapters) do
    local words = index.chapter_words(ch)
    local bar = ""
    if ch.target and ch.target > 0 then
      local pct = math.floor(words / ch.target * 100)
      local filled = math.floor(pct / 10)
      bar = (" ▕%s%s▏%3d%%"):format(string.rep("█", filled), string.rep("░", 10 - filled), pct)
    end
    local label = ("%02d %-30s %6d w%s"):format(ch.number or 0, ch.title or ch.filename, words, bar)
    table.insert(entries, { value = ch, display = label })
  end
  pickers.pick_list(entries, {
    prompt_title = "Storyteller outline",
    on_select = function(ch)
      vim.cmd("edit " .. vim.fn.fnameescape(ch.path))
    end,
  })
end

return M