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
--     s     select scene status
--     u     mark scene unused (status: unused)
--     R     rebuild buffer content

local project = require("storyteller.project")
local index = require("storyteller.index")
local metadata = require("storyteller.metadata")
local scene_data = require("storyteller.scene")

local M = {}
local NS = vim.api.nvim_create_namespace("StorytellerCorkboard")

local STATUS_ORDER = { "outline", "draft", "revision", "done" }
local NEXT_STATUS = {
  outline = "draft",
  draft = "revision",
  revision = "done",
  done = "outline",
}

local STATUS_HL = {
  outline = "StorytellerCorkboardOutline",
  draft = "StorytellerCorkboardDraft",
  revision = "StorytellerCorkboardRevision",
  done = "StorytellerCorkboardDone",
  unused = "StorytellerCorkboardUnused",
}

local function ensure_highlights()
  local set = vim.api.nvim_set_hl
  set(0, "StorytellerCorkboardHeader", { link = "Title", default = true })
  set(0, "StorytellerCorkboardHelp", { link = "Comment", default = true })
  set(0, "StorytellerCorkboardChapter", { link = "Special", default = true })
  set(0, "StorytellerCorkboardScene", { link = "Identifier", default = true })
  set(0, "StorytellerCorkboardWords", { link = "Number", default = true })
  set(0, "StorytellerCorkboardOutline", { link = "Comment", default = true })
  set(0, "StorytellerCorkboardDraft", { link = "String", default = true })
  set(0, "StorytellerCorkboardRevision", { link = "WarningMsg", default = true })
  set(0, "StorytellerCorkboardDone", { link = "DiagnosticOk", default = true })
  set(0, "StorytellerCorkboardUnused", { link = "DiagnosticError", default = true })
end

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
  local local_meta = scene_data.from_index(sc).meta
  if local_meta.status then
    return clean(local_meta.status)
  end
  local m = metadata.read(sc.path)
  return clean(m and m.meta and m.meta.status)
end

local function scene_pov(sc)
  local local_meta = scene_data.from_index(sc).meta
  if local_meta.pov then
    return clean(local_meta.pov)
  end
  local m = metadata.read(sc.path)
  return clean(m and m.meta and m.meta.pov) or clean(sc.meta and sc.meta.pov)
end

local function scene_location(sc)
  local local_meta = scene_data.from_index(sc).meta
  if local_meta.location then
    return clean(local_meta.location)
  end
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
  ensure_highlights()
  vim.api.nvim_buf_clear_namespace(bufnr, NS, 0, -1)
  cb.rows = build_rows(cb.prj, cb.filter)
  cb.line_to = {}

  local lines = {}
  lines[#lines + 1] = "Storyteller corkboard — " .. (cb.prj.root or "")
  lines[#lines + 1] = "── <CR> open · s status · u unused · R rebuild · q close ──"

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
  vim.api.nvim_buf_add_highlight(bufnr, NS, "StorytellerCorkboardHeader", 0, 0, -1)
  vim.api.nvim_buf_add_highlight(bufnr, NS, "StorytellerCorkboardHelp", 1, 0, -1)
  for line, row in pairs(cb.line_to) do
    local index = line - 1
    local status = row.status ~= "" and row.status or "outline"
    local status_end = #status + 2 -- [status]
    vim.api.nvim_buf_add_highlight(bufnr, NS, STATUS_HL[status] or "StorytellerCorkboardOutline", index, 0, status_end)
    local scene_start = status_end + 1
    local scene_end = lines[line]:find(" — ", scene_start, true)
    if scene_end then
      vim.api.nvim_buf_add_highlight(bufnr, NS, "StorytellerCorkboardScene", index, scene_start, scene_end - 1)
    end
    local words_start = lines[line]:find("%d+ words")
    if words_start then
      vim.api.nvim_buf_add_highlight(bufnr, NS, "StorytellerCorkboardWords", index, words_start - 1, -1)
    end
  end
  for line, text in ipairs(lines) do
    if text:match("^### ") then
      vim.api.nvim_buf_add_highlight(bufnr, NS, "StorytellerCorkboardChapter", line - 1, 0, -1)
    end
  end
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
  scene_data.update(row.sc, { status = next })
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
  vim.ui.select({ "mark unused", "cancel" }, {
    prompt = ("Mark scene '%s' unused?"):format(row.sc.title or vim.fn.fnamemodify(row.sc.path, ":t")),
  }, function(choice)
    if choice == "mark unused" then
      scene_data.update(row.sc, { status = "unused" })
      M.refresh(bufnr)
    end
  end)
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
  end, { buffer = bufnr, silent = true, desc = "Open scene" })

  vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = bufnr, silent = true, desc = "Close corkboard" })

  vim.keymap.set("n", "u", function()
    M.mark_unused(bufnr)
  end, { buffer = bufnr, silent = true, desc = "Mark scene unused" })

  vim.keymap.set("n", "s", function()
    local cb = vim.b[bufnr].storyteller_corkboard
    local row = cb and cb.line_to[vim.api.nvim_win_get_cursor(0)[1]]
    if not row then
      return
    end
    vim.ui.select({ "outline", "draft", "revision", "done", "unused" }, {
      prompt = ("Status for '%s'"):format(row.sc.title or vim.fn.fnamemodify(row.sc.path, ":t")),
    }, function(status)
      if status then
        scene_data.update(row.sc, { status = status })
        M.refresh(bufnr)
      end
    end)
  end, { buffer = bufnr, silent = true, desc = "Set scene status" })

  vim.keymap.set("n", "R", function()
    M.refresh(bufnr)
  end, { buffer = bufnr, silent = true, desc = "Refresh corkboard" })
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
  vim.api.nvim_buf_set_name(bufnr, "storyteller://corkboard/" .. vim.fn.fnamemodify(prj.root, ":t"))
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
  vim.wo.number = false
  vim.wo.relativenumber = false
  vim.wo.signcolumn = "no"
  vim.wo.wrap = false
  vim.wo.cursorline = true
  M.refresh(bufnr)
  setup_keys(bufnr)
  return bufnr
end

return M
