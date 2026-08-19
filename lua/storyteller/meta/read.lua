-- storyteller.meta.read
-- Read metadata from chapter frontmatter and scene YAML blocks, with legacy
-- inline `- **Key:**` bullets as a fallback. No writes happen here.
--
-- Reads are mtime-cached so a multi-scene scan of a chapter reads the file
-- once; a later on-disk change (new mtime) transparently re-reads it.

local serde = require("storyteller.meta.serde")

local M = {}

-- path -> { mtime = number, lines = table }
local lines_cache = {}

local function read_lines(path)
  if path == "" then
    return nil
  end
  local stat = vim.loop.fs_stat(path)
  if not stat then
    return nil
  end
  local mtime = stat.mtime.sec
  local cached = lines_cache[path]
  if cached and cached.mtime == mtime then
    return cached.lines
  end
  local lines = vim.fn.readfile(path)
  lines_cache[path] = { mtime = mtime, lines = lines }
  return lines
end

-- Chapter frontmatter document.
-- Returns { path, meta, body, had_block, [frontmatter], [original_meta] } or
-- nil when the file is unreadable.
function M.chapter(path)
  local lines = read_lines(path)
  if not lines then
    return nil
  end
  local parsed = serde.parse_frontmatter(lines)
  if not parsed then
    return { path = path, meta = {}, body = lines, had_block = false }
  end
  return {
    path = path,
    meta = parsed.meta,
    original_meta = vim.deepcopy(parsed.meta),
    frontmatter = vim.list_slice(lines, 1, parsed.close),
    body = vim.list_slice(lines, parsed.body_start),
    had_block = true,
  }
end

-- Parse a scene's YAML block. Returns { meta, content_start, ... }.
function M.scene_block(lines, start_line, end_line)
  return serde.parse_scene_block(lines, start_line, end_line)
end

-- Collect inline `- **Key:** value` bullets from a scene's body.
function M.inline(lines, start_line, end_line)
  local out = {}
  for i = start_line, end_line do
    local line = lines[i] or ""
    local key, value = serde.parse_inline(line)
    if key and value then
      out[key:lower()] = serde.scalar(value)
    end
  end
  return out
end

-- Fully resolved metadata for a scene: chapter frontmatter defaults are
-- overridden by inline bullets, which are overridden by the scene YAML block.
function M.scene(scene)
  local lines = read_lines(scene.path) or {}
  local block = serde.parse_scene_block(lines, scene.start_line, scene.end_line or #lines)
  local inline = M.inline(lines, scene.start_line, scene.end_line or #lines)
  local chapter = M.chapter(scene.path)
  local chapter_meta = chapter and chapter.meta or {}
  local meta = vim.tbl_extend("force", {}, chapter_meta, inline, block.meta)
  return vim.tbl_extend("force", block, {
    meta = meta,
    inline = inline,
    chapter = chapter_meta,
  })
end

-- Resolve one field for a scene (scene -> chapter -> default).
function M.field(scene, key, default)
  local value = M.scene(scene).meta[key]
  if value == nil then
    return default
  end
  return value
end

return M
