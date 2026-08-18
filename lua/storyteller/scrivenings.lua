-- storyteller.scrivenings
-- Two-way "scrivenings" view: all chapters are compiled into a single
-- `buftype="acwrite"` buffer, and `:w` (via BufWriteCmd) writes each
-- chapter's slice back to its per-chapter file.
--
--   scrivenings.open(prj[, opts])   compile or re-enter the compiled buffer
--
-- Buffer dict: b:storyteller_scrivenings = { prj, chunks[] } where each chunk
-- is { chapter_path, start, end, indent, header, snapshot }.

local project = require("storyteller.project")
local index = require("storyteller.index")
local command = require("storyteller.command")

local M = {}

-- prj.root -> bufnr of the open scrivening view for that project.
local open_buffers = {}

local function project_name(path)
  return vim.fn.fnamemodify(path, ":t")
end

local function chapter_title(ch)
  return ch.title or vim.fn.fnamemodify(ch.path, ":t:r")
end

local function not_in_project()
  vim.notify("[storyteller] Not in a storytelling project.", vim.log.levels.WARN)
end

-- Compile the joined buffer for `prj`. Chapters are taken in index order
-- (lexical). Each chapter is preceded by "# <title>" + a blank separator and
-- followed by a blank line; those two separator lines are NOT part of the
-- slice that gets written back.
local function compile(prj)
  local chapters = index.chapters(prj)
  if #chapters == 0 then
    vim.notify("[storyteller] No chapters to compile.", vim.log.levels.WARN)
    return nil
  end

  local lines = {}
  local chunks = {}
  for _, ch in ipairs(chapters) do
    local header = "# " .. chapter_title(ch)
    lines[#lines + 1] = header
    lines[#lines + 1] = ""
    local body = vim.fn.readfile(ch.path)
    if not body then
      body = {}
    end
    local start = #lines + 1
    vim.list_extend(lines, body)
    local stop = #lines
    lines[#lines + 1] = "" -- inter-chapter blank
    chunks[#chunks + 1] = {
      chapter_path = ch.path,
      header = header,
      start = start,
      ["end"] = stop,
      indent = 0,
      snapshot = vim.list_slice(lines, start, stop),
    }
  end
  return { lines = lines, chunks = chunks }
end

local function find_line(lines, hdr, from)
  for i = from or 1, #lines do
    if lines[i] == hdr then
      return i
    end
  end
  return nil
end

-- Re-sync each chunk's slice against the *current* buffer (edits shift line
-- numbers, so boundaries are recomputed off the chapter separators on every
-- save), then write back any slice whose lines differ from the snapshot
-- captured at compile time. Returns the chapter files actually rewritten.
local function writeback(buf)
  local st = vim.b[buf].storyteller_scrivenings
  if not st then
    return {}
  end
  local chunks = st.chunks
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local n = #lines
  local written = {}
  local pos = 1
  for i, chunk in ipairs(chunks) do
    local next_chunk = chunks[i + 1]
    local hp = find_line(lines, chunk.header, pos)
    if hp then
      local stop
      if next_chunk then
        local np = find_line(lines, next_chunk.header, hp + 1)
        if np then
          stop = np - 1
          if stop >= 1 and lines[stop] == "" then
            stop = stop - 1
          end
        else
          stop = n
        end
      else
        stop = n
        if stop >= 1 and lines[stop] == "" then
          stop = stop - 1
        end
      end
      local start = hp + 2
      if stop < start - 1 then
        stop = start - 1
      end
      local slice
      if stop >= start then
        slice = vim.list_slice(lines, start, stop)
      else
        slice = {}
      end
      if not vim.deep_equal(slice, chunk.snapshot) then
        vim.fn.writefile(slice, chunk.chapter_path)
        written[#written + 1] = chunk.chapter_path
      end
      chunk.snapshot = slice
      chunk.start = start
      chunk["end"] = stop
      pos = hp + 1
    end
    -- A lost header line means we simply skip writing that chunk; the cursor
    -- keeps advancing so later chunks are still mapped correctly.
  end
  vim.bo[buf].modified = false
  return written
end

-- Open (or re-enter) the scrivenings buffer for `prj`.
-- opts.bang rebuilds from scratch instead of re-entering the existing buffer.
M.open = function(prj, opts)
  prj = prj or project.current()
  opts = opts or {}
  if not prj then
    not_in_project()
    return nil
  end

  local existing = open_buffers[prj.root]
  if not opts.bang and existing and vim.api.nvim_buf_is_valid(existing) then
    vim.api.nvim_set_current_buf(existing)
    return existing
  end

  if existing and vim.api.nvim_buf_is_valid(existing) then
    vim.api.nvim_buf_delete(existing, { force = true })
    open_buffers[prj.root] = nil
  end

  local doc = compile(prj)
  if not doc then
    return nil
  end

  local buf = vim.api.nvim_create_buf(false, false)
  vim.api.nvim_buf_set_name(buf, "storyteller://scrivenings/" .. project_name(prj.root))
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, doc.lines)
  vim.bo[buf].buftype = "acwrite"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].modifiable = true

  vim.b[buf].storyteller_scrivenings = { prj = prj, chunks = doc.chunks }

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = buf,
    callback = function(ev)
      local written = writeback(ev.buf)
      if #written > 0 then
        vim.notify(
          ("[storyteller] Scrivenings: wrote %d chapter(s)."):format(#written),
          vim.log.levels.INFO
        )
      end
    end,
  })

  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = buf,
    callback = function()
      if open_buffers[prj.root] == buf then
        open_buffers[prj.root] = nil
      end
    end,
  })

  open_buffers[prj.root] = buf
  vim.api.nvim_set_current_buf(buf)
  return buf
end

M.save = writeback
M.compile = compile

-- :StoryScrivenings (and :StoryScrivenings! to recompile a fresh copy).
M.setup = function()
  command.register("Scrivenings", function(opts)
    local prj = project.current()
    if not prj then
      not_in_project()
      return
    end
    M.open(prj, { bang = opts and opts.bang or false })
  end, {
    desc = "Open/refresh the scrivenings view of all chapters",
    opts = { nargs = 0, bang = true },
  })
end

return M