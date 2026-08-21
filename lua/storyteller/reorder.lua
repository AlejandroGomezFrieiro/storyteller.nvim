-- storyteller.reorder
-- Scrivener-style structural edits: reorder scenes within a chapter and move
-- scenes across chapters. All operations rewrite markdown files on disk and
-- reload any buffers showing those files. Nothing touches metadata semantics —
-- a scene's YAML block travels with its text.

local project = require("storyteller.project")
local index = require("storyteller.index")

local M = {}

-- Reload every loaded buffer for `path` from disk (discarding their contents,
-- not user edits: we refuse to run when such buffers are modified).
local function reload_buffers(path, lines)
  for _, b in ipairs(vim.fn.getbufinfo({ bufloaded = 1 })) do
    if vim.api.nvim_buf_get_name(b.bufnr) == path then
      if b.changed ~= 0 then
        vim.bo[b.bufnr].readonly = true
        error(
          "[storyteller] unsaved edits in "
            .. vim.fn.fnamemodify(path, ":t")
            .. "; buffer made read-only."
        )
      end
      vim.api.nvim_buf_set_lines(b.bufnr, 0, -1, false, lines)
      vim.bo[b.bufnr].modified = false
    end
  end
end

local function read_fresh(path)
  return vim.fn.readfile(path)
end

local function write(path, lines)
  vim.fn.writefile(lines, path)
  index.invalidate()
  reload_buffers(path, lines)
end

-- Split a chapter body into { pre, blocks, gaps } where blocks[i] is the
-- scene i text (heading included) and gaps[i] is the whitespace between
-- scene i and scene i+1 (kept attached after each block).
local function split_scenes(lines, first_start)
  local pre = {}
  for i = 1, (first_start or 1) - 1 do
    pre[#pre + 1] = lines[i]
  end
  local starts = {}
  for i, ln in ipairs(lines) do
    if ln:match("^##%s+") then
      starts[#starts + 1] = i
    end
  end
  if #starts == 0 then
    return { pre = pre, blocks = {}, gaps = {} }
  end
  local blocks, gaps = {}, {}
  for k, s in ipairs(starts) do
    local e = starts[k + 1] and (starts[k + 1] - 1) or #lines
    local blk = {}
    for i = s, e do
      blk[#blk + 1] = lines[i]
    end
    -- Trim trailing blanks into the gap so joins stay tidy.
    while #blk > 1 and blk[#blk] == "" do
      blk[#blk] = nil
      e = e - 1
    end
    blocks[k] = blk
    local g = {}
    if k < #starts then
      for i = e + 1, starts[k + 1] - 1 do
        g[#g + 1] = lines[i]
      end
      if #g == 0 then
        g[1] = ""
      end
    end
    gaps[k] = g
  end
  return { pre = pre, blocks = blocks, gaps = gaps }
end

local function join_parts(parts)
  local out = {}
  for _, l in ipairs(parts.pre) do
    out[#out + 1] = l
  end
  for i, blk in ipairs(parts.blocks) do
    for _, l in ipairs(blk) do
      out[#out + 1] = l
    end
    if parts.gaps[i] then
      for _, l in ipairs(parts.gaps[i]) do
        out[#out + 1] = l
      end
    elseif i < #parts.blocks then
      out[#out + 1] = ""
    end
  end
  return out
end

local function find_scene(scenes, sc)
  for i, s in ipairs(scenes) do
    if s.path == sc.path and s.start_line == sc.start_line then
      return i
    end
  end
  return nil
end

-- Move scene at index i by delta (-1 up / +1 down) through the global scene
-- order. Returns the list of files rewritten.
function M.move(prj, sc, delta)
  prj = prj or project.current()
  if not prj then
    return nil
  end
  local scenes = index.scenes(prj)
  local i = find_scene(scenes, sc)
  if not i then
    vim.notify("[storyteller] Scene not found in the index.", vim.log.levels.WARN)
    return nil
  end
  local j = i + delta
  local other = scenes[j]
  if not other then
    return {}
  end
  if other.path == sc.path then
    return M.swap_in_file(sc.path, sc.start_line, other.start_line)
  end
  if delta < 0 then
    -- Move sc before `other`.
    return M.move_to_file(sc, other.path, other.start_line, "before")
  end
  return M.move_to_file(sc, other.path, other.end_line, "after")
end

-- Swap two scene blocks inside one file (by heading line numbers).
function M.swap_in_file(path, start_a, start_b)
  local lines = read_fresh(path)
  local parts = split_scenes(lines, nil)
  -- Match headings by their line content.
  local ia, ib = nil, nil
  for k, blk in ipairs(parts.blocks) do
    local head = blk[1]
    if head == lines[start_a] and not ia then
      ia = k
    elseif head == lines[start_b] and not ib then
      ib = k
    end
  end
  if not (ia and ib) then
    vim.notify("[storyteller] Could not locate both scenes.", vim.log.levels.ERROR)
    return nil
  end
  parts.blocks[ia], parts.blocks[ib] = parts.blocks[ib], parts.blocks[ia]
  write(path, join_parts(parts))
  return { path }
end

-- Move scene `sc` into file `target` before/at line `anchor`.
function M.move_to_file(sc, target, anchor, where)
  local src = read_fresh(sc.path)
  -- Extract the block [heading .. next heading).
  local s = sc.start_line
  local e = s
  for i = s + 1, #src do
    if src[i]:match("^##%s+") then
      break
    end
    e = i
  end
  while e > s and src[e] == "" do
    e = e - 1
  end
  local block = {}
  for i = s, e do
    block[#block + 1] = src[i]
  end
  -- Remove from source (also drop one following blank if present).
  local rest = {}
  for i = 1, s - 1 do
    rest[#rest + 1] = src[i]
  end
  local skip_to = e
  if src[e + 1] == "" then
    skip_to = e + 1
  end
  for i = skip_to + 1, #src do
    rest[#rest + 1] = src[i]
  end
  write(sc.path, rest)

  -- Insert into the destination at the anchor.
  local dst = read_fresh(target)
  local at = anchor
  if where == "after" then
    at = anchor + 1
  end
  local out = {}
  for i = 1, at - 1 do
    out[#out + 1] = dst[i]
  end
  -- Normalize blank separation around the inserted block.
  while #out > 0 and out[#out] == "" do
    out[#out] = nil
  end
  if #out > 0 then
    out[#out + 1] = ""
  end
  for _, l in ipairs(block) do
    out[#out + 1] = l
  end
  out[#out + 1] = ""
  for i = at, #dst do
    out[#out + 1] = dst[i]
  end
  -- Collapse any triple blanks introduced at the seam.
  local clean = {}
  local blanks = 0
  for _, l in ipairs(out) do
    if l == "" then
      blanks = blanks + 1
      if blanks <= 2 then
        clean[#clean + 1] = l
      end
    else
      blanks = 0
      clean[#clean + 1] = l
    end
  end
  write(target, clean)
  return { sc.path, target }
end

-- Shared with the projection engine (storyteller.projections): structural
-- rewrites rebuild files from scene blocks.
M.split_scenes = split_scenes
M.join_parts = join_parts

-- Persist rewritten chapter lines: refuse modified buffers (made read-only),
-- write, invalidate the index, and reload clean buffers from disk.
function M.write_file(path, lines)
  reload_buffers(path, lines)
  vim.fn.writefile(lines, path)
  index.invalidate()
end

return M
