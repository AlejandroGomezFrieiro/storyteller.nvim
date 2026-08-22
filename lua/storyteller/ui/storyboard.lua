-- storyteller.ui.storyboard
-- A projection as an ordinary editing surface: the rendered text sits in an
-- `acwrite` buffer where every vim key works — dd/y/p move cards, / searches,
-- visual-block edits sweep the metadata sheet. On `:w` the buffer is diffed
-- against its baseline and the resulting operations are applied atomically
-- (docs/interaction.md, docs/projections.md).

local project = require("storyteller.project")
local schema = require("storyteller.schema")
local index = require("storyteller.index")
local projections = require("storyteller.projections")
local board_hl = require("storyteller.ui.board_hl")

local M = {}

-- bufnr -> { name, prj, baseline = lines[] }
local state = {}

-- Restyle after any buffer mutation (edits, moves, commits).
local function repaint()
  local buf = vim.api.nvim_get_current_buf()
  local b = state[buf]
  if b then
    board_hl.paint(buf, b.name)
  end
end

local TITLES = {
  corkboard = "Corkboard",
  timeline = "Timeline",
  synopsis = "Synopsis",
  metasheet = "Metadata sheet",
}

local function board(buf)
  return state[buf]
end

-- --- Buffer helpers ----------------------------------------------------------

-- Card bounds around the cursor: from the nearest `## ` header at/above to
-- just before the next one. Returns s, e.
local function card_bounds(lines, lnum)
  local s = nil
  for i = lnum, 1, -1 do
    if lines[i]:match("^##%s+") then
      s = i
      break
    end
  end
  if not s then
    return nil
  end
  local e = #lines
  for i = s + 1, #lines do
    if lines[i]:match("^##%s+") then
      e = i - 1
      break
    end
  end
  while e > s and lines[e] == "" do
    e = e - 1
  end
  return s, e
end

-- Shift the day cell of the timeline row under the cursor by `delta`
-- (staged until :w). Unscheduled rows (·) and non-numeric coordinates
-- (ordinal axes, secondary placements) are refused — there is no neighbor
-- relation to infer for them.
function M.shift_day(delta)
  local buf = vim.api.nvim_get_current_buf()
  local b = board(buf)
  if not b then
    return
  end
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local ln = lines[lnum] or ""
  if not ln:find("|", 1, true) then
    return
  end
  local day, rest = ln:match("^(%S+)(|.*)$")
  if not day then
    return
  end
  if day:sub(-1) == "*" then
    vim.notify(
      "[storyteller] Secondary (also:) placement — edit it in the scene YAML.",
      vim.log.levels.INFO
    )
    return
  end
  local value = tonumber(day)
  if not value then
    vim.notify(
      "[storyteller] Non-numeric coordinate — retime ordinal axes in the scene YAML.",
      vim.log.levels.INFO
    )
    return
  end
  local shifted = tostring(value + delta)
  local padded = shifted .. string.rep(" ", #day - #shifted)
  vim.api.nvim_buf_set_lines(buf, lnum - 1, lnum, false, { padded .. rest })
  vim.notify(("[storyteller] day → %s (:w to apply)"):format(shifted), vim.log.levels.INFO)
end

-- Move the block under the cursor down (+1) or up (-1) within the buffer.
function M.move_block(delta)
  local buf = vim.api.nvim_get_current_buf()
  if not board(buf) then
    return
  end
  if state[buf].name == "timeline" then
    return M.shift_day(delta)
  end
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local has_cards = false
  for _, ln in ipairs(lines) do
    if ln:match("^##%s+") then
      has_cards = true
      break
    end
  end

  if not has_cards then
    -- Row mode (timeline/metasheet): swap single lines past the neighbor.
    local other = lnum + delta
    if other < 1 or other > #lines or not lines[other]:find("|", 1, true) then
      return
    end
    lines[lnum], lines[other] = lines[other], lines[lnum]
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    board_hl.paint(buf, state[buf].name)
    vim.api.nvim_win_set_cursor(0, { other, 0 })
    return
  end

  local s, e = card_bounds(lines, lnum)
  if not s then
    return
  end
  if delta > 0 then
    local n_s, n_e = card_bounds(lines, math.min(e + 2, #lines))
    if not (n_s and n_s > e) then
      return
    end
    local out = {}
    for i = 1, s - 1 do
      out[#out + 1] = lines[i]
    end
    for i = n_s, n_e do
      out[#out + 1] = lines[i]
    end
    out[#out + 1] = ""
    for i = s, e do
      out[#out + 1] = lines[i]
    end
    for i = n_e + 1, #lines do
      out[#out + 1] = lines[i]
    end
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, out)
    board_hl.paint(buf, state[buf].name)
    vim.api.nvim_win_set_cursor(0, { s + (n_e - n_s) + 2, 0 })
  else
    -- Find the previous card's start by scanning above.
    local p_s = nil
    for i = s - 1, 1, -1 do
      if lines[i]:match("^##%s+") then
        p_s = i
        break
      end
    end
    if not p_s then
      return
    end
    local p_e = s - 1
    while p_e > p_s and lines[p_e] == "" do
      p_e = p_e - 1
    end
    local out = {}
    for i = 1, p_s - 1 do
      out[#out + 1] = lines[i]
    end
    for i = s, e do
      out[#out + 1] = lines[i]
    end
    for i = p_s, p_e do
      out[#out + 1] = lines[i]
    end
    for i = e + 1, #lines do
      out[#out + 1] = lines[i]
    end
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, out)
    board_hl.paint(buf, state[buf].name)
    vim.api.nvim_win_set_cursor(0, { p_s, 0 })
  end
end

-- Cycle the status field of the card/row under the cursor (staged until :w).
function M.cycle_status()
  local buf = vim.api.nvim_get_current_buf()
  if not board(buf) then
    return
  end
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local s, e = card_bounds(lines, lnum)
  if not s then
    s, e = lnum, lnum
  end
  for i = s, e do
    local cur = lines[i]:match("^status:%s*(%S+)")
    if cur then
      local next = schema.next_status(cur)
      lines[i] = ("status: %s"):format(next)
      vim.api.nvim_buf_set_lines(buf, i - 1, i, false, { lines[i] })
      board_hl.paint(buf, state[buf].name)
      vim.notify(("[storyteller] status → %s (:w to apply)"):format(next), vim.log.levels.INFO)
      return
    end
  end
  vim.notify("[storyteller] No status line under the cursor.", vim.log.levels.WARN)
end

-- Open the scene under the cursor in place of the board.
function M.open_scene()
  local buf = vim.api.nvim_get_current_buf()
  local b = board(buf)
  if not b then
    return
  end
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local title
  for i = lnum, 1, -1 do
    title = lines[i]:match("^#+%s+(.+)$")
    if title then
      break
    end
  end
  if not title then
    return
  end
  title = vim.trim(title:gsub("%s*·%s*.*$", ""):gsub(" #%d+$", ""))
  for _, sc in ipairs(index.scenes(b.prj)) do
    if sc.title == title then
      index.open_scene(sc)
      return
    end
  end
  vim.notify("[storyteller] No scene named " .. title, vim.log.levels.WARN)
end

-- --- Commit ------------------------------------------------------------------

local function commit(buf)
  local b = board(buf)
  if not b then
    return
  end
  local cur = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local applied, err = projections.commit(b.name, b.prj, b.baseline, cur)
  if not applied then
    vim.notify("[storyteller] Apply failed: " .. tostring(err), vim.log.levels.ERROR)
    return
  end
  if applied == 0 then
    vim.bo[buf].modified = false
    vim.notify("[storyteller] No changes.", vim.log.levels.INFO)
    return
  end
  -- Re-render from disk so annotations (word counts) and normalization land.
  local out = projections.render(b.name, b.prj)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, out.lines)
  b.baseline = out.lines
  vim.bo[buf].modified = false
  board_hl.paint(buf, b.name)
  vim.notify(("[storyteller] Applied %d change(s)."):format(applied), vim.log.levels.INFO)
end

local function refresh(buf, force)
  local b = board(buf)
  if not b then
    return
  end
  if vim.bo[buf].modified and not force then
    local answer = vim.fn.confirm("[storyteller] Discard unapplied edits?", "&Discard\n&Cancel", 2)
    if answer ~= 1 then
      return
    end
  end
  local out, rerr = projections.render(b.name, b.prj, b.axis)
  if not out then
    vim.notify("[storyteller] Render failed: " .. tostring(rerr), vim.log.levels.ERROR)
    return
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, out.lines)
  b.baseline = out.lines
  vim.bo[buf].modified = false
  board_hl.paint(buf, b.name)
end

-- --- Open --------------------------------------------------------------------

function M.open(name, prj, axis)
  prj = prj or project.current()
  if not prj then
    vim.notify("[storyteller] Not in a storytelling project.", vim.log.levels.WARN)
    return nil
  end
  schema.load(prj.root)

  local out, err = projections.render(name, prj, axis)
  if not out then
    vim.notify("[storyteller] " .. tostring(err), vim.log.levels.ERROR)
    return nil
  end

  local buf = vim.api.nvim_create_buf(false, true)
  local board_name = "storyteller://"
    .. name
    .. (axis and ("/" .. axis) or "")
    .. "/"
    .. vim.fn.fnamemodify(prj.root, ":t")
  pcall(vim.api.nvim_buf_set_name, buf, board_name)
  vim.bo[buf].buftype = "acwrite"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "storyteller-board"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, out.lines)
  state[buf] = { name = name, prj = prj, axis = axis, baseline = out.lines }
  -- Commands chain naturally from a board (e.g. :Story timeline Past).
  vim.b[buf].storyteller_project = prj
  board_hl.paint(buf, name)

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = buf,
    callback = function()
      commit(buf)
    end,
  })
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    buffer = buf,
    callback = vim.schedule_wrap(repaint),
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = buf,
    once = true,
    callback = function()
      state[buf] = nil
    end,
  })

  local opts = { buffer = buf, silent = true }
  vim.keymap.set("n", "J", function()
    M.move_block(1)
  end, vim.tbl_extend("force", opts, { desc = "Move item down" }))
  vim.keymap.set("n", "K", function()
    M.move_block(-1)
  end, vim.tbl_extend("force", opts, { desc = "Move item up" }))
  vim.keymap.set("n", "a", M.cycle_status, vim.tbl_extend("force", opts, { desc = "Cycle status" }))
  vim.keymap.set("n", "<CR>", M.open_scene, vim.tbl_extend("force", opts, { desc = "Open scene" }))
  vim.keymap.set("n", "R", function()
    refresh(buf, true)
  end, vim.tbl_extend("force", opts, { desc = "Re-render from disk" }))
  vim.keymap.set("n", "q", function()
    if vim.bo[buf].modified then
      local answer =
        vim.fn.confirm("[storyteller] Discard unapplied edits?", "&Discard\n&Cancel", 2)
      if answer ~= 1 then
        return
      end
    end
    vim.cmd("close")
  end, vim.tbl_extend("force", opts, { desc = "Close" }))

  vim.wo.number = false
  vim.wo.relativenumber = false
  vim.wo.wrap = false
  vim.wo.cursorline = true
  vim.wo.winbar = "%#StorytellerTitle# "
    .. (TITLES[name] or name)
    .. " %#StorytellerMuted :w apply · J/K move · a status · <CR> open · R refresh · q close"

  vim.api.nvim_set_current_buf(buf)
  return buf
end

return M
