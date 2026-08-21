-- storyteller.notes
-- Markdown-file-backed annotations. Instead of sprinkling `%%comments%%`
-- through the prose, notes live in their own document — by default
-- `notes/annotations.md` — and each entry points back to its source:
--
--   ## Fix the pacing
--
--   ```yaml
--   storyteller: note
--   status: open
--   file: chapters/01_the_harbor.md
--   line: 14
--   created: 2026-08-21
--   ```
--
--   > Odysseus watched the harbor lights bend in the rain.
--
--   The reveal comes too late — consider cutting the second sentence.
--
-- The manuscript stays clean; exports never see notes (the file lives outside
-- chapters/). Legacy inline `%%annotations%%` are still stripped on compile
-- and still surface in the review view.

local project = require("storyteller.project")
local config = require("storyteller.config")

local M = {}

local function join(...)
  return table.concat({ ... }, "/")
end

function M.notes_file(prj)
  prj = prj or project.current()
  if not prj then
    return nil
  end
  local rel = config.get().notes_file or "notes/annotations.md"
  return join(prj.root, rel)
end

local function today()
  return os.date("%Y-%m-%d")
end

-- --- Parsing -----------------------------------------------------------------

-- Parse the notes document into entries. Returns { entry, ... } where each
-- entry carries its exact line span so edits can rewrite it precisely.
function M.parse(lines)
  local entries = {}
  local i = 1
  while i <= #lines do
    local title = lines[i]:match("^##%s+(.+)%s*$")
    if title then
      -- Find the yaml block (if any) directly below the heading.
      local j = i + 1
      while j <= #lines and lines[j]:match("^%s*$") do
        j = j + 1
      end
      local meta, block_end = {}, nil
      if lines[j] == "```yaml" then
        local k = j + 1
        while k <= #lines and lines[k] ~= "```" do
          local key, value = lines[k]:match("^%s*([%w_]+):%s*(.*)$")
          if key and value ~= "" then
            meta[key] = value
          end
          k = k + 1
        end
        block_end = k
        if not (meta.storyteller or ""):match("^note") then
          meta = {}
          block_end = nil
        end
      end

      if meta.storyteller then
        -- Entry body runs until the next `## ` heading.
        local body_start = (block_end or i) + 1
        local e = body_start
        while e <= #lines and not lines[e]:match("^##%s+") do
          e = e + 1
        end
        local quote, body = nil, {}
        local in_body = false
        for l = body_start, e - 1 do
          local q = lines[l]:match("^>%s?(.*)$")
          if q and quote == nil then
            quote = q
            in_body = true
          elseif in_body and not (lines[l]:match("^%s*$") and #body == 0) then
            body[#body + 1] = lines[l]
          end
        end
        while body[#body] == "" do
          body[#body] = nil
        end
        entries[#entries + 1] = {
          title = title,
          status = meta.status or "open",
          file = meta.file,
          line = tonumber(meta.line),
          created = meta.created,
          quote = quote,
          body = body,
          -- spans into the notes document for precise rewriting
          heading_line = i,
          start_line = i,
          ["end"] = math.min(e - 1, #lines),
        }
        i = e
      else
        i = i + 1
      end
    else
      i = i + 1
    end
  end
  return entries
end

function M.list(prj)
  prj = prj or project.current()
  local path = M.notes_file(prj)
  if not (path and vim.loop.fs_stat(path)) then
    return {}
  end
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    return {}
  end
  return M.parse(lines)
end

-- --- Writing -----------------------------------------------------------------

local function render(entry)
  local out = {}
  out[#out + 1] = "## " .. entry.title
  out[#out + 1] = ""
  out[#out + 1] = "```yaml"
  out[#out + 1] = "storyteller: note"
  out[#out + 1] = "status: " .. (entry.status or "open")
  if entry.file then
    out[#out + 1] = "file: " .. entry.file
  end
  if entry.line then
    out[#out + 1] = "line: " .. entry.line
  end
  out[#out + 1] = "created: " .. (entry.created or today())
  out[#out + 1] = "```"
  out[#out + 1] = ""
  if entry.quote then
    out[#out + 1] = "> " .. entry.quote
    out[#out + 1] = ""
  end
  for _, l in ipairs(entry.body or {}) do
    out[#out + 1] = l
  end
  return out
end

local function read_or_new(path)
  if vim.loop.fs_stat(path) then
    return vim.fn.readfile(path)
  end
  return {
    "# Annotations",
    "",
    "Notes captured while writing. Each entry points back to its source;",
    "the manuscript itself stays clean.",
    "",
  }
end

local function write_notes(path, lines)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  vim.fn.writefile(lines, path)
end

-- Append a new annotation. Returns the entry.
function M.add(prj, opts)
  prj = prj or project.current()
  local path = M.notes_file(prj)
  if not path then
    return nil
  end
  opts = opts or {}
  local entry = {
    title = opts.title or "Untitled note",
    status = "open",
    file = opts.file,
    line = opts.line,
    created = today(),
    quote = opts.quote,
    body = opts.body or {},
  }
  local lines = read_or_new(path)
  while lines[#lines] == "" do
    lines[#lines] = nil
  end
  vim.list_extend(lines, { "" })
  vim.list_extend(lines, render(entry))
  write_notes(path, lines)
  return entry
end

-- Rewrite one entry in place (by identity of its heading line).
function M.update(prj, entry, changes)
  local path = M.notes_file(prj)
  if not (path and vim.loop.fs_stat(path)) then
    return false
  end
  local lines = vim.fn.readfile(path)
  local all = M.parse(lines)
  for _, e in ipairs(all) do
    if e.heading_line == entry.heading_line then
      for k, v in pairs(changes) do
        e[k] = v
      end
      local replacement = render(e)
      -- Replace [start_line..end]; keep exactly one blank line after.
      local tail = {}
      for l = entry["end"] + 1, #lines do
        tail[#tail + 1] = lines[l]
      end
      while tail[1] == "" do
        table.remove(tail, 1)
      end
      local out = {}
      for l = 1, entry.start_line - 1 do
        out[#out + 1] = lines[l]
      end
      vim.list_extend(out, replacement)
      vim.list_extend(out, { "" })
      vim.list_extend(out, tail)
      write_notes(path, out)
      return true
    end
  end
  return false
end

-- Remove an entry entirely.
function M.delete(prj, entry)
  local path = M.notes_file(prj)
  if not (path and vim.loop.fs_stat(path)) then
    return false
  end
  local lines = vim.fn.readfile(path)
  local out = {}
  for l = 1, #lines do
    if l < entry.start_line or l > entry["end"] then
      out[#out + 1] = lines[l]
    end
  end
  -- Trim trailing blanks left behind by the removal.
  while out[#out] == "" do
    out[#out] = nil
  end
  write_notes(path, out)
  return true
end

-- Toggle open/resolved.
M.toggle_status = function(prj, entry)
  return M.update(prj, entry, { status = entry.status == "open" and "resolved" or "open" })
end

-- --- Jumping back to the source ----------------------------------------------

-- Open the source file and land on the quoted text when we can find it
-- (recorded line numbers drift as the prose is edited).
function M.jump(entry)
  if not entry.file then
    vim.notify("[storyteller] This note has no source file.", vim.log.levels.WARN)
    return
  end
  vim.cmd("edit " .. vim.fn.fnameescape(entry.file))
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local target = entry.line or 1
  if entry.quote and entry.quote ~= "" then
    -- Search outward from the recorded line for the quoted text.
    for radius = 0, 40 do
      for _, li in ipairs({ target - radius, target + radius }) do
        local ln = lines[li]
        if ln and ln:find(entry.quote, 1, true) then
          vim.api.nvim_win_set_cursor(0, { li, 0 })
          vim.cmd("normal! zz")
          return
        end
      end
    end
  end
  vim.api.nvim_win_set_cursor(0, { math.min(target, #lines), 0 })
  vim.cmd("normal! zz")
end

-- --- Capture from a buffer ---------------------------------------------------

-- Build an entry from the current buffer: a visual selection, or the cursor's
-- line when in normal mode.
function M.capture(prj, title)
  local buf = vim.api.nvim_get_current_buf()
  local file = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":.")
  if file == "" then
    vim.notify("[storyteller] No file under the cursor.", vim.log.levels.WARN)
    return nil
  end
  local mode = vim.fn.mode()
  local start_line, end_line, quote
  if mode:match("[vV]") then
    -- Leave visual mode first so the marks settle.
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "x", false)
    start_line = vim.api.nvim_buf_get_mark(0, "<")[1]
    end_line = vim.api.nvim_buf_get_mark(0, ">")[1]
  else
    start_line = vim.api.nvim_win_get_cursor(0)[1]
    end_line = start_line
  end
  local sel = vim.api.nvim_buf_get_lines(buf, start_line - 1, end_line, false)
  quote = vim.trim(table.concat(sel, " "))
  if quote == "" then
    vim.notify("[storyteller] Nothing selected.", vim.log.levels.WARN)
    return nil
  end
  if #quote > 120 then
    quote = quote:sub(1, 117) .. "…"
  end
  title = title and title ~= "" and title
    or ("Note on “" .. vim.fn.strcharpart(quote, 0, 32) .. "”")
  return M.add(prj, {
    title = title,
    file = file,
    line = start_line,
    quote = quote,
  })
end

return M
