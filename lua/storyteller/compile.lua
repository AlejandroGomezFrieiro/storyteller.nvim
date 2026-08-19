-- storyteller.compile
-- Unified compilation: a metadata-free longform manuscript, the two-way
-- "Scrivenings" editable view, and Pandoc export.
--
--   compile.manuscript(prj)      -> metadata-free longform lines
--   compile.write_manuscript(prj)-> write build/manuscript.md
--   compile.open(prj, {bang})    -> editable continuous manuscript buffer
--   compile.export(prj, fmt)     -> pandoc manuscript export
--   compile.export_all(prj, fmt) -> per-chapter export

local project = require("storyteller.project")
local index = require("storyteller.index")
local config = require("storyteller.config")

local M = {}

local VALID = { docx = true, epub = true, pdf = true, smf = true }

local function join(...)
  return table.concat({ ... }, "/")
end

-- --- Metadata stripping -----------------------------------------------------

-- Turn chapter lines into prose-only lines:
--   * drop the leading YAML front matter (-----------...-----------)
--   * drop ```yaml storyteller: scene``` metadata blocks
--   * drop inline `- **Key:** value` metadata bullets
--   * drop `- [ ]` planning checklists
-- Everything else (headings, prose, real lists, non-scene code fences)
-- is preserved verbatim.
function M.strip_metadata(lines)
  local out = {}
  local start = 1
  if (lines[1] or ""):match("^%s*%-%-%-%s*$") then
    for i = 2, #lines do
      if (lines[i] or ""):match("^%s*%-%-%-%s*$") then
        start = i + 1
        break
      end
    end
  end
  local in_scene_yaml = false
  for i = start, #lines do
    local ln = lines[i]
    if ln == "```yaml" then
      if (lines[i + 1] or ""):match("^storyteller: scene%s*$") then
        in_scene_yaml = true
      else
        out[#out + 1] = ln
      end
    elseif in_scene_yaml then
      if ln == "```" then
        in_scene_yaml = false
      end
    else
      local inline = ln:match("^%s*%-%s*%*%*%s*[%a%w_]+%s*[:]%s*%*%*") ~= nil
        or ln:match("^%s*%-%s*%*%*%s*[%a%w_]+%s*%*%*%s*:")
      if not inline and not ln:match("^%s*%-%s*%[[ xX]%]%s*") then
        out[#out + 1] = ln
      end
    end
  end
  return out
end

-- --- Manuscript -------------------------------------------------------------

-- Metadata-free longform for the whole project.
function M.manuscript(prj)
  prj = prj or project.current()
  local out = {}
  for _, ch in ipairs(index.chapters(prj)) do
    local raw = vim.fn.readfile(ch.path) or {}
    vim.list_extend(out, M.strip_metadata(raw))
    out[#out + 1] = ""
    out[#out + 1] = ""
  end
  return out
end

function M.write_manuscript(prj)
  prj = prj or project.current()
  if not prj then
    return nil
  end
  vim.fn.mkdir(prj.build, "p")
  local path = join(prj.build, "manuscript.md")
  vim.fn.writefile(M.manuscript(prj), path)
  return path
end

-- --- Scrivenings (editable join + write-back) -------------------------------

local open_buffers = {}

local function project_name(path)
  return vim.fn.fnamemodify(path, ":t")
end

local function chapter_title(ch)
  return ch.title or vim.fn.fnamemodify(ch.path, ":t:r")
end

-- Compile the joined buffer. Chapters in index order, each preceded by
-- "# <title>" + blank, followed by blank. Separator lines are not written back.
local function compile_join(prj)
  local chapters = index.chapters(prj)
  if #chapters == 0 then
    return nil
  end
  local lines = {}
  local chunks = {}
  for _, ch in ipairs(chapters) do
    local header = "# " .. chapter_title(ch)
    lines[#lines + 1] = header
    lines[#lines + 1] = ""
    local body = vim.fn.readfile(ch.path) or {}
    local start = #lines + 1
    vim.list_extend(lines, body)
    local stop = #lines
    lines[#lines + 1] = ""
    chunks[#chunks + 1] = {
      chapter_path = ch.path,
      header = header,
      start = start,
      ["end"] = stop,
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

local function sync_source_buffers(path, lines)
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_get_name(bufnr) == path then
      if vim.bo[bufnr].modified then
        vim.bo[bufnr].readonly = true
        vim.b[bufnr].storyteller_scrivenings_conflict = true
        vim.notify(
          ("[storyteller] Scrivenings wrote %s; its modified buffer is now read-only.")
            :format(vim.fn.fnamemodify(path, ":t")),
          vim.log.levels.WARN
        )
      else
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
        vim.bo[bufnr].modified = false
        vim.b[bufnr].storyteller_scrivenings_conflict = nil
      end
    end
  end
end

-- Re-sync each chunk's slice against the current buffer, then write back any
-- slice that changed. Returns the chapter files actually rewritten.
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
        sync_source_buffers(chunk.chapter_path, slice)
        written[#written + 1] = chunk.chapter_path
      end
      chunk.snapshot = slice
      chunk.start = start
      chunk["end"] = stop
      pos = hp + 1
    end
  end
  vim.bo[buf].modified = false
  return written
end

-- Open (or re-enter) the scrivenings buffer for `prj`.
function M.open(prj, opts)
  prj = prj or project.current()
  opts = opts or {}
  if not prj then
    vim.notify("[storyteller] Not in a storytelling project.", vim.log.levels.WARN)
    return nil
  end

  local existing = open_buffers[prj.root]
  if not opts.bang and existing and vim.api.nvim_buf_is_valid(existing) then
    vim.api.nvim_set_current_buf(existing)
    return existing
  end

  if existing and vim.api.nvim_buf_is_valid(existing) then
    if vim.bo[existing].modified and opts.bang then
      local answer = vim.fn.confirm("Discard unsaved Scrivenings edits and rebuild?", "&Discard\n&Cancel", 2)
      if answer ~= 1 then
        vim.api.nvim_set_current_buf(existing)
        return existing
      end
    end
    vim.api.nvim_buf_delete(existing, { force = true })
    open_buffers[prj.root] = nil
  end

  local doc = compile_join(prj)
  if not doc then
    vim.notify("[storyteller] No chapters to compile.", vim.log.levels.WARN)
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

-- --- Export ----------------------------------------------------------------

local function reference_doc()
  local candidates = {}
  local function add(p)
    if p and p ~= "" then
      candidates[#candidates + 1] = p
    end
  end
  add(join(vim.fn.getcwd(), "templates/storyteller/reference.docx"))
  for _, base in ipairs(vim.opt.runtimepath:get() or {}) do
    if base ~= "" then
      add(join(base, "templates/storyteller/reference.docx"))
      add(join(base, "reference.docx"))
    end
  end
  for _, p in ipairs(candidates) do
    if vim.loop.fs_stat(p) then
      return p
    end
  end
  return nil
end

local function have_pandoc()
  return vim.fn.executable("pandoc") == 1
end

local function run_pandoc(args)
  local parts = { "pandoc" }
  for _, a in ipairs(args) do
    parts[#parts + 1] = a
  end
  vim.fn.system(parts)
  return vim.v.shell_error == 0
end

local function check_fmt(fmt)
  if not fmt or fmt == "" then
    fmt = "docx"
  end
  fmt = fmt:lower()
  if not VALID[fmt] then
    vim.notify(
      ("[storyteller] Unknown export format '%s' (docx, epub, pdf, smf)"):format(tostring(fmt)),
      vim.log.levels.ERROR
    )
    return nil
  end
  return fmt
end

local function require_prj(prj)
  prj = prj or project.current()
  if not prj then
    vim.notify("[storyteller] Not in a storytelling project.", vim.log.levels.WARN)
    return nil
  end
  return prj
end

local function filestem(path)
  return vim.fn.fnamemodify(path, ":t:r")
end

-- Export a single markdown file (metadata stripped). Returns output path.
function M.export_file(prj, file, fmt)
  fmt = check_fmt(fmt)
  if not fmt then
    return nil
  end
  prj = require_prj(prj)
  if not prj then
    return nil
  end
  if not have_pandoc() then
    vim.notify("[storyteller] pandoc not found; install pandoc to export.", vim.log.levels.ERROR)
    return nil
  end
  vim.fn.mkdir(prj.build, "p")
  local target = fmt == "smf" and "docx" or fmt
  local base = filestem(file)
  local out = join(prj.build, base .. "." .. target)
  local src = join(prj.build, "." .. base .. ".storyteller-src.md")
  vim.fn.writefile(M.strip_metadata(vim.fn.readfile(file) or {}), src)
  local args = {
    tostring(src),
    "--to=" .. tostring(target),
    "--output=" .. tostring(out),
  }
  if fmt == "smf" then
    local ref = reference_doc()
    if ref then
      args[#args + 1] = "--reference-doc=" .. ref
    else
      vim.notify("[storyteller] No reference.docx found; exporting smf without a reference doc.", vim.log.levels.WARN)
    end
  end
  local ok = run_pandoc(args)
  vim.fn.delete(src)
  if not ok then
    vim.notify("[storyteller] pandoc failed.", vim.log.levels.ERROR)
    return nil
  end
  return out
end

-- Stitch chapters into build/manuscript.md, then export.
function M.export(prj, fmt)
  fmt = check_fmt(fmt)
  if not fmt then
    return nil
  end
  prj = require_prj(prj)
  if not prj then
    return nil
  end
  if not have_pandoc() then
    vim.notify("[storyteller] pandoc not found; manuscript export unavailable.", vim.log.levels.ERROR)
    return nil
  end
  vim.fn.mkdir(prj.build, "p")
  local target = fmt == "smf" and "docx" or fmt
  local ms = join(prj.build, "manuscript.md")
  vim.fn.writefile(M.manuscript(prj), ms)
  local out = join(prj.build, "manuscript." .. target)
  local args = {
    ms,
    "--to=" .. tostring(target),
    "--output=" .. tostring(out),
  }
  if fmt == "smf" then
    local ref = reference_doc()
    if ref then
      args[#args + 1] = "--reference-doc=" .. ref
    else
      vim.notify("[storyteller] No reference.docx found; smf exported without a reference doc.", vim.log.levels.WARN)
    end
  end
  local ok = run_pandoc(args)
  if not ok then
    vim.notify("[storyteller] pandoc failed.", vim.log.levels.ERROR)
    return nil
  end
  return out
end

-- Export every chapter individually.
function M.export_all(prj, fmt)
  prj = require_prj(prj)
  if not prj then
    return nil
  end
  local out = {}
  for _, ch in ipairs(index.chapters(prj)) do
    local path = M.export_file(prj, ch.path, fmt)
    if path then
      out[#out + 1] = path
    end
  end
  return out
end

-- Aliases used across the codebase.
M.save = writeback
M.compile = compile_join

return M
