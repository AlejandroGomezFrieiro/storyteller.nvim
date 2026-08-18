-- storyteller.corkboard
-- A nofile, wipe-on-close buffer that lists every scene in a project as a
-- "card". Each row:
--     [status] <scene title> — <pov> — <n words> [ · <location>]
-- with status/pov/location from chapter frontmatter + inline metadata.
--
-- Buffer-local state on `vim.b[<bufnr>].storyteller_corkboard`:
--     { prj = ..., filter = ..., rows = {...}, line_to = { [lineno] = row } }
--
-- Keymaps (buffer-local):
--     <CR>  open that scene at its heading line
--     d     mark scene unused (status: unused)
--     a     cycle status: outline → draft → revision → done
--     R     rebuild buffer content

local project = require("storyteller.project")
local index = require("storyteller.index")
local metadata = require("storyteller.metadata")

local M = {}

local STATUS_ORDER = { "outline", "draft", "revision", "done" }
local NEXT_STATUS = {
  outline = "draft",
  draft = "revision",
  revision = "done",
  done = "outline",
}

local function trim(s)
  return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function clean(value)
  local s = trim(value)
  if s == "" then
    return nil
  end
  return s
end

local function scene_status(sc)
  local m = metadata.read(sc.path)
  return clean(m and m.meta and m.meta.status)
end

local function scene_pov(sc)
  return clean(sc.meta and sc.meta.pov)
end

local function scene_location(sc)
  local m = metadata.read(sc.path)
  return clean(m and m.meta and m.meta.location) or clean(sc.meta and sc.meta.location)
end

-- Build rows for the project (subsetting by `filter` on the label text).
local function build_rows(prj, filter)
  local rows = {}
  local lf = filter and filter:lower() or ""
  for _, sc in ipairs(index.scenes(prj)) do
    local status = scene_status(sc)
    local pov = scene_pov(sc)
    local loc = scene_location(sc)
    local label = ("%s — %s — %d words"):format(sc.title or "(untitled)", pov or "?", sc.words or 0)
    if loc then
      label = label .. " · " .. loc
    end
    if lf == "" or label:lower():find(lf, 1, true) then
      table.insert(rows, {
        sc = sc,
        status = status or "",
        pov = pov or "",
        location = loc or "",
        words = sc.words or 0,
        label = label,
      })
    end
  end
  return rows
end

-- (Re)write the corkboard content into the buffer.
M.refresh = function(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local cb = vim.b[bufnr].storyteller_corkboard
  if not cb then
    return
  end

  vim.bo[bufnr].modifiable = true
  cb.rows = build_rows(cb.prj, cb.filter)
  cb.line_to = {}

  local lines = {}
  lines[#lines + 1] = "Storyteller corkboard — " .. (cb.prj.root or "")
  lines[#lines + 1] = "── <CR> open scene · a cycle status · d mark unused · R rebuild ──"

  local lastpath = nil
  for _, row in ipairs(cb.rows) do
    if row.sc.path ~= lastpath then
      lastpath = row.sc.path
      local name = vim.fn.fnamemodify(row.sc.path, ":t")
      if name == "" then
        name = row.sc.path
      end
      lines[#lines + 1] = "### " .. name
    end
    lines[#lines + 1] = ("[%s] %s"):format(row.status, row.label)
    cb.line_to[#lines] = row
  end

  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = false
  -- nvim buf var access returns a copy; write the mutated state back.
  vim.b[bufnr].storyteller_corkboard = cb
end

-- Advance a row's `status` through outline → draft → revision → done.
M.toggle_status = function(bufnr, line)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local cb = vim.b[bufnr].storyteller_corkboard
  if not cb then
    return
  end
  line = line or vim.api.nvim_win_get_cursor(0)[1]
  local row = cb.line_to[line]
  if not row then
    return
  end
  local next = NEXT_STATUS[trim(row.status)] or STATUS_ORDER[1]
  metadata.set(row.sc.path, "status", next)
  M.refresh(bufnr)
end

-- Set a scene's status to `unused` and rebuild.
M.mark_unused = function(bufnr, line)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local cb = vim.b[bufnr].storyteller_corkboard
  if not cb then
    return
  end
  line = line or vim.api.nvim_win_get_cursor(0)[1]
  local row = cb.line_to[line]
  if not row then
    return
  end
  metadata.set(row.sc.path, "status", "unused")
  M.refresh(bufnr)
end

-- Open the scene under the cursor at its heading line.
local function open_at(bufnr)
  local cb = vim.b[bufnr].storyteller_corkboard
  if not cb then
    return
  end
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local row = cb.line_to[line]
  if not row then
    return
  end
  vim.cmd("edit " .. vim.fn.fnameescape(row.sc.path))
  vim.api.nvim_win_set_cursor(0, { row.sc.start_line, 0 })
  vim.cmd("normal! zt")
end

-- Wire the buffer-local keymaps.
local function setup_keys(bufnr)
  vim.keymap.set("n", "<CR>", function()
    open_at(bufnr)
  end, { buffer = bufnr, silent = true })

  vim.keymap.set("n", "d", function()
    M.mark_unused(bufnr)
  end, { buffer = bufnr, silent = true })

  vim.keymap.set("n", "a", function()
    M.toggle_status(bufnr)
  end, { buffer = bufnr, silent = true })

  vim.keymap.set("n", "R", function()
    M.refresh(bufnr)
  end, { buffer = bufnr, silent = true })
end

-- Open (or focus an existing) corkboard for a project. Optional filter text.
M.open = function(prj, filter)
  prj = prj or project.current()
  if not prj then
    vim.notify("[storyteller] Not in a storytelling project.", vim.log.levels.WARN)
    return nil
  end

  -- Reuse an existing corkboard buffer if one is already open.
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.b[b].storyteller_corkboard then
      vim.api.nvim_set_current_buf(b)
      local cb = vim.b[b].storyteller_corkboard
      cb.prj = prj
      cb.filter = filter or ""
      M.refresh(b)
      return b
    end
  end

  local bufnr = vim.api.nvim_create_buf(false, true)
  local bo = vim.bo[bufnr]
  bo.buftype = "nofile"
  bo.bufhidden = "wipe"
  bo.modifiable = true
  bo.swapfile = false
  bo.filetype = "storyl-corkboard"

  vim.b[bufnr].storyteller_corkboard = {
    prj = prj,
    root = prj.root,
    filter = filter or "",
    rows = {},
    line_to = {},
  }
  vim.api.nvim_set_current_buf(bufnr)
  M.refresh(bufnr)
  setup_keys(bufnr)
  return bufnr
end

return M