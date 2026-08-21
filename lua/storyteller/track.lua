-- storyteller.track
-- Writing sessions, a daily progress log, and the derived tracking stats that
-- power the dashboard: heatmap, streaks, and milestones.
--
-- progress.log lines: `YYYY-MM-DD <delta> <total>`. The cumulative total makes
-- later daily deltas correct across multi-day gaps. Older two-column rows are
-- read but cannot supply a reliable baseline.

local project = require("storyteller.project")
local index = require("storyteller.index")

local M = {}

local function join(...)
  return table.concat({ ... }, "/")
end

-- --- Word totals ------------------------------------------------------------

function M.total_words(prj)
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

-- --- Sessions ---------------------------------------------------------------

function M.session_start()
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

function M.session_stats()
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

function M.session_end()
  local stats = M.session_stats()
  if not stats then
    vim.notify("[storyteller] No active session.", vim.log.levels.WARN)
    return
  end
  M.progress_append()
  vim.notify(
    ("[storyteller] Session ended · wrote %d words (since %s)."):format(
      stats.written,
      stats.started_at
    ),
    vim.log.levels.INFO
  )
  vim.g.storyteller_session = nil
end

-- --- Daily progress log -----------------------------------------------------

function M.progress_append(prj)
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

  local prev_total = 0
  for _, ln in ipairs(lines) do
    local date, _, total = ln:match("^(%d%d%d%d%-%d%d%-%d%d)%s+(%d+)%s+(%d+)")
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
      out[#out + 1] = ("%s %d %d"):format(today, delta, current)
      updated = true
    else
      out[#out + 1] = ln
    end
  end
  if not updated then
    out[#out + 1] = ("%s %d %d"):format(today, delta, current)
  end
  vim.fn.writefile(out, logfile)
  vim.notify(
    ("[storyteller] progress.log updated · %s → +%d words (total %d)."):format(
      today,
      delta,
      current
    ),
    vim.log.levels.INFO
  )
  return { logfile = logfile, delta = delta, total = current }
end

-- Parse progress.log into { date, delta, total } rows (3-column only).
function M.log_entries(prj)
  prj = prj or project.current()
  local logfile = prj and join(prj.root, "progress.log") or nil
  local entries = {}
  if not (logfile and vim.loop.fs_stat(logfile)) then
    return entries
  end
  for _, ln in ipairs(vim.fn.readfile(logfile)) do
    local date, delta, total = ln:match("^(%d%d%d%d%-%d%d%-%d%d)%s+(%d+)%s+(%d+)")
    if date then
      entries[#entries + 1] = {
        date = date,
        delta = tonumber(delta),
        total = tonumber(total),
      }
    end
  end
  return entries
end

-- --- Heatmap & streaks ------------------------------------------------------

-- Daily word deltas keyed by date for the last `weeks` weeks (default 30).
function M.heatmap(prj, weeks)
  prj = prj or project.current()
  weeks = weeks or 30
  local by_date = {}
  for _, e in ipairs(M.log_entries(prj)) do
    by_date[e.date] = e.delta
  end
  local now = os.time()
  local out = {}
  for day = (weeks * 7) - 1, 0, -1 do
    local t = now - day * 86400
    local date = os.date("%Y-%m-%d", t)
    out[#out + 1] = { date = date, delta = by_date[date] or 0 }
  end
  return out
end

function M.activity_summary(prj)
  local entries = M.log_entries(prj)
  local active, words, best = 0, 0, nil
  for _, entry in ipairs(entries) do
    if entry.delta and entry.delta > 0 then
      active = active + 1
      words = words + entry.delta
      if not best or entry.delta > best.delta then
        best = entry
      end
    end
  end
  return {
    active_days = active,
    logged_words = words,
    average = active > 0 and math.floor(words / active) or 0,
    best_day = best,
  }
end

-- GitHub-style grid: weeks as columns, Sun..Sat as rows. Newest day (today)
-- lands in the final column. `months[w]` labels the column where a new month
-- begins, like a contribution graph.
function M.week_grid(prj, weeks)
  prj = prj or project.current()
  weeks = weeks or 30
  local by_date = {}
  for _, e in ipairs(M.log_entries(prj)) do
    by_date[e.date] = e.delta or 0
  end
  local now = os.time()
  local today_dow = tonumber(os.date("%w", now))
  local grid = {}
  local months = {}
  local last_month = nil
  for w = 1, weeks do
    grid[w] = {}
    local first = nil
    for d = 0, 6 do
      local offset = (weeks - w) * 7 + (today_dow - d)
      if offset >= 0 then
        local t = now - offset * 86400
        local date = os.date("%Y-%m-%d", t)
        local cell = { date = date, delta = by_date[date] or 0 }
        grid[w][d] = cell
        if not first then
          first = cell
        end
      end
    end
    if first then
      local month_num = tonumber(first.date:sub(6, 7))
      if month_num ~= last_month then
        months[w] = os.date(
          "%b",
          os.time({
            year = tonumber(first.date:sub(1, 4)),
            month = month_num,
            day = 1,
          })
        )
        last_month = month_num
      end
    end
  end
  return { grid = grid, months = months, weeks = weeks }
end

-- Current and longest writing streaks (consecutive days with a positive delta).
function M.streaks(prj)
  prj = prj or project.current()
  local by_date = {}
  for _, e in ipairs(M.log_entries(prj)) do
    if e.delta and e.delta > 0 then
      by_date[e.date] = true
    end
  end

  local function day_number(date)
    local y, m, d = date:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    return os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d) })
  end

  local days = {}
  for date in pairs(by_date) do
    days[#days + 1] = date
  end
  table.sort(days)

  local longest, run = 0, 0
  local prev = nil
  for _, date in ipairs(days) do
    if prev and day_number(date) - day_number(prev) == 86400 then
      run = run + 1
    else
      run = 1
    end
    if run > longest then
      longest = run
    end
    prev = date
  end

  -- Current streak: count backwards from today (or yesterday if today is empty).
  local current = 0
  local cursor = os.time()
  if not by_date[os.date("%Y-%m-%d", cursor)] then
    cursor = cursor - 86400
  end
  while by_date[os.date("%Y-%m-%d", cursor)] do
    current = current + 1
    cursor = cursor - 86400
  end

  return { current = current, longest = longest }
end

-- --- Milestones -------------------------------------------------------------

-- Light gamification: a list of { id, name, done } derived from the project.
function M.milestones(prj)
  prj = prj or project.current()
  local total = M.total_words(prj)
  local entries = M.log_entries(prj)
  local sessions = #entries
  local streaks = M.streaks(prj)

  local function mk(id, name, done)
    return { id = id, name = name, done = done }
  end

  return {
    mk("words-1k", "Write 1,000 words", total >= 1000),
    mk("words-10k", "Write 10,000 words", total >= 10000),
    mk("words-50k", "Write 50,000 words (a novel)", total >= 50000),
    mk("words-100k", "Write 100,000 words", total >= 100000),
    mk("sessions-10", "Complete 10 sessions", sessions >= 10),
    mk("streak-3", "3-day writing streak", streaks.current >= 3),
    mk("streak-7", "7-day writing streak", streaks.current >= 7),
    mk("streak-30", "30-day writing streak", streaks.current >= 30),
  }
end

-- --- POV / character / tag coverage -----------------------------------------

-- Per-scene POV distribution, per-character appearance counts, and tag usage
-- counts, all ranked descending. Powers the "balance" section of the report
-- and the tracking view.
function M.pov_balance(prj)
  prj = prj or project.current()
  local povs, chars, tags = {}, {}, {}
  local total = 0
  for _, sc in ipairs(index.scenes(prj)) do
    total = total + 1
    local m = sc.meta or {}
    local pov = m.pov
    if type(pov) == "table" then
      pov = pov[1]
    end
    if pov and pov ~= "" then
      povs[pov] = (povs[pov] or 0) + 1
    end
    for _, c in ipairs(m.chars or {}) do
      if c and c ~= "" then
        chars[c] = (chars[c] or 0) + 1
      end
    end
    for _, t in ipairs(m.tags or {}) do
      if t and t ~= "" then
        tags[t] = (tags[t] or 0) + 1
      end
    end
  end
  local function ranked(t)
    local keys = {}
    for k in pairs(t) do
      keys[#keys + 1] = k
    end
    table.sort(keys, function(a, b)
      local ca, cb = t[a] or 0, t[b] or 0
      if ca ~= cb then
        return ca > cb
      end
      return a < b
    end)
    return keys
  end
  return {
    total_scenes = total,
    povs = povs,
    characters = chars,
    tags = tags,
    pov_order = ranked(povs),
    char_order = ranked(chars),
    tag_order = ranked(tags),
  }
end

-- --- Plain-text report (fallback dashboard) ---------------------------------

function M.report(prj)
  prj = prj or project.current()
  local out = {}
  out[#out + 1] = "# Tracking — " .. (prj and vim.fn.fnamemodify(prj.root, ":t") or "?")
  out[#out + 1] = ""
  out[#out + 1] = ("Total words: %d"):format(M.total_words(prj))
  local sum_target = 0
  for _, ch in ipairs(index.chapters(prj)) do
    local words = index.chapter_words(ch)
    local target = ch.target or 0
    sum_target = sum_target + target
    local pct = target > 0 and math.floor(words / target * 100) or 0
    out[#out + 1] = ("  %s · %d/%d (%d%%)"):format(ch.title or ch.filename, words, target, pct)
  end
  out[#out + 1] = ""
  if sum_target > 0 then
    out[#out + 1] = ("Manuscript target: %d · current %d words"):format(
      sum_target,
      M.total_words(prj)
    )
  end
  local s = M.session_stats()
  if s then
    out[#out + 1] = ("Session: since %s · %d words written."):format(s.started_at, s.written)
  end
  local streaks = M.streaks(prj)
  out[#out + 1] = ("Streak: %d current · %d longest"):format(streaks.current, streaks.longest)
  local balance = M.pov_balance(prj)
  if #balance.pov_order > 0 then
    out[#out + 1] = ""
    out[#out + 1] = "## POV balance"
    for _, pov in ipairs(balance.pov_order) do
      local n = balance.povs[pov]
      local pct = balance.total_scenes > 0 and math.floor(n / balance.total_scenes * 100) or 0
      out[#out + 1] = ("  %-24s %3d scenes (%d%%)"):format(pov, n, pct)
    end
  end
  if #balance.char_order > 0 then
    out[#out + 1] = ""
    out[#out + 1] = "## Characters"
    for _, c in ipairs(balance.char_order) do
      out[#out + 1] = ("  %-24s %3d scenes"):format(c, balance.characters[c])
    end
  end
  if #balance.tag_order > 0 then
    out[#out + 1] = ""
    out[#out + 1] = "## Tags"
    for _, t in ipairs(balance.tag_order) do
      out[#out + 1] = ("  %-24s %3d scenes"):format(t, balance.tags[t])
    end
  end
  local recent = M.heatmap(prj, 1)
  out[#out + 1] = ""
  out[#out + 1] = "## Last 7 days"
  for i = math.max(1, #recent - 6), #recent do
    out[#out + 1] = ("  %s  %5d words"):format(recent[i].date, recent[i].delta)
  end
  return table.concat(out, "\n")
end

return M
