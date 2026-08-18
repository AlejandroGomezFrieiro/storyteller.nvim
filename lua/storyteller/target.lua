-- storyteller.target
-- Writing targets, session tracking, and a daily progress log.
--
--   target.total_words(prj)        sum of chapter words
--   target.session_stats()         { started_at, start_words, written }
--   target.progress_append(prj)    append/update today's delta in progress.log
--   target.dashboard(prj)          open a nofile report buffer (targets + log)

local project = require("storyteller.project")
local index = require("storyteller.index")

local M = {}

local function join(...)
  return table.concat({ ... }, "/")
end

-- Total words across all chapters (prose only, best effort via index).
M.total_words = function(prj)
  prj = prj or project.current()
  if not prj then
    return 0
  end
  local total = 0
  for _, ch in ipairs(index.chapters(prj)) do
    total = total + index.chapter_words(ch)
  end
  return total
end

-- --- Session tracking -------------------------------------------------------

-- Begin a writing session, recording the project's current total words.
M.session_start = function()
  local prj = project.current()
  if not prj then
    vim.notify("[storyteller] Not in a storytelling project.", vim.log.levels.WARN)
    return nil
  end
  vim.g.storyteller_session = {
    root = prj.root,
    started_at = os.date("%Y-%m-%d %H:%M"),
    start_words = M.total_words(prj),
  }
  vim.notify("[storyteller] Session started.", vim.log.levels.INFO)
  return vim.g.storyteller_session
end

M.session_stats = function()
  local s = vim.g.storyteller_session
  if not s then
    return nil
  end
  local current = M.total_words()
  return {
    root = s.root,
    started_at = s.started_at,
    start_words = s.start_words,
    written = math.max(0, current - s.start_words),
  }
end

-- End the session: append to progress.log and notify the session delta.
M.session_end = function()
  local stats = M.session_stats()
  if not stats then
    vim.notify("[storyteller] No active session.", vim.log.levels.WARN)
    return
  end
  M.progress_append()
  vim.notify(
    ("[storyteller] Session ended · wrote %d words (since %s)."):format(stats.written, stats.started_at),
    vim.log.levels.INFO
  )
  vim.g.storyteller_session = nil
end

-- --- Daily progress log -----------------------------------------------------

-- progress.log lines: `YYYY-MM-DD <words>` where <words> is that day's delta.
-- Idempotent per day: if today's line exists it is replaced with a recomputed
-- value (current total minus the previous day's total); else appended.
M.progress_append = function(prj)
  prj = prj or project.current()
  if not prj then
    vim.notify("[storyteller] Not in a storytelling project.", vim.log.levels.WARN)
    return nil
  end
  local logfile = join(prj.root, "progress.log")
  local lines = {}
  if vim.loop.fs_stat(logfile) then
    lines = vim.fn.readfile(logfile)
  end
  local today = os.date("%Y-%m-%d")
  local current = M.total_words(prj)

  -- Find the previous day's total (last non-today line) to compute today's delta.
  local prev_total = 0
  for _, ln in ipairs(lines) do
    local date, total = ln:match("^(%d%d%d%d%-%d%d%-%d%d)%s+(%d+)")
    if date and date ~= today then
      prev_total = tonumber(total) or prev_total
    end
  end
  local delta = math.max(0, current - prev_total)

  local updated = false
  local out = {}
  for _, ln in ipairs(lines) do
    local date = ln:match("^(%d%d%d%d%-%d%d%-%d%d)%s")
    if date == today then
      table.insert(out, ("%s %d"):format(today, delta))
      updated = true
    else
      table.insert(out, ln)
    end
  end
  if not updated then
    table.insert(out, ("%s %d"):format(today, delta))
  end
  vim.fn.writefile(out, logfile)
  vim.notify(
    ("[storyteller] progress.log updated · %s → +%d words (total %d)."):format(today, delta, current),
    vim.log.levels.INFO
  )
  return { logfile = logfile, delta = delta, total = current }
end

-- --- Dashboard report -------------------------------------------------------

-- Build the report text for a project.
M.report = function(prj)
  prj = prj or project.current()
  local out = {}
  table.insert(out, "# Targets — " .. (prj and vim.fn.fnamemodify(prj.root, ":t") or "?"))
  table.insert(out, "")
  table.insert(out, ("Total words: %d"):format(M.total_words(prj)))
  local sum_target = 0
  for _, ch in ipairs(index.chapters(prj)) do
    local words = index.chapter_words(ch)
    local target = ch.target or 0
    sum_target = sum_target + target
    local pct = target > 0 and math.floor(words / target * 100) or 0
    table.insert(
      out,
      ("  %s %s · %d/%d (%d%%)"):format(ch.title or ch.filename, ch.scenes and ("[" .. #ch.scenes .. " scenes]") or "", words, target, pct)
    )
  end
  table.insert(out, "")
  if sum_target > 0 then
    table.insert(out, ("Manuscript target: %d · current %d words"):format(sum_target, M.total_words(prj)))
  end
  local s = M.session_stats()
  if s then
    table.insert(out, ("Session: since %s · %d words written."):format(s.started_at, s.written))
  end
  -- last 7 days from progress.log
  local logfile = prj and join(prj.root, "progress.log") or nil
  local recent = {}
  if logfile and vim.loop.fs_stat(logfile) then
    for _, ln in ipairs(vim.fn.readfile(logfile)) do
      local date, words = ln:match("^(%d%d%d%d%-%d%d%-%d%d)%s+(%d+)")
      if date and words then
        recent[#recent + 1] = { date = date, words = tonumber(words) }
      end
    end
  end
  if #recent > 0 then
    table.insert(out, "")
    table.insert(out, "## Last 7 days")
    table.insert(out, "")
    local start = math.max(1, #recent - 6)
    for i = start, #recent do
      table.insert(out, ("  %s  %5d words"):format(recent[i].date, recent[i].words))
    end
  end
  return table.concat(out, "\n")
end

-- Open a nofile report buffer (regen on demand via `:StoryTargets`).
M.dashboard = function(prj)
  prj = prj or project.current()
  if not prj then
    vim.notify("[storyteller] Not in a storytelling project.", vim.log.levels.WARN)
    return nil
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, "storyteller://targets/" .. vim.fn.fnamemodify(prj.root, ":t"))
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(M.report(prj), "\n"))
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = false
  vim.keymap.set("n", "R", function()
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(M.report(prj), "\n"))
    vim.bo[buf].modifiable = false
  end, { buffer = buf, desc = "Refresh targets dashboard" })
  vim.api.nvim_set_current_buf(buf)
  return buf
end

return M