-- storyteller.meta.write
-- Mutate metadata and persist it, preserving comments and unsupported YAML.
-- Also migrates legacy inline `- **Key:**` bullets into scene YAML blocks.
--
-- Note: read and write share no function names (`chapter`/`scene` belong to
-- read; `chapter_write`/`scene_write` belong here) so meta/init.lua can merge
-- the two modules without collision.

local serde = require("storyteller.meta.serde")
local schema = require("storyteller.schema")
local read = require("storyteller.meta.read")

local M = {}

-- Keep any clean open buffers aligned with what we just wrote to disk.
function M.sync_clean_buffers(path, lines)
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if
      vim.api.nvim_buf_is_valid(bufnr)
      and vim.api.nvim_buf_get_name(bufnr) == path
      and not vim.bo[bufnr].modified
    then
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
      vim.bo[bufnr].modified = false
    end
  end
end

local function writefile(path, lines)
  vim.fn.writefile(lines, path)
  M.sync_clean_buffers(path, lines)
end

function M.new_id(scene)
  local seed = table.concat({ scene.path, scene.title or "", tostring(vim.uv.hrtime()) }, ":")
  return vim.fn.sha256(seed):sub(1, 12)
end

-- Merge a patch into chapter frontmatter. Returns the merged meta.
-- `vim.NIL` removes a managed field instead of writing it.
function M.chapter_write(path, patch)
  local doc = read.chapter(path)
  if not doc then
    return nil
  end
  doc.meta = doc.meta or {}
  for k, v in pairs(patch or {}) do
    if v == vim.NIL then
      doc.meta[k] = nil
    else
      doc.meta[k] = v
    end
  end
  local new_lines = {}
  if doc.had_block and doc.frontmatter and doc.original_meta then
    vim.list_extend(
      new_lines,
      serde.patch_frontmatter(doc.frontmatter, doc.original_meta, doc.meta)
    )
  elseif not vim.tbl_isempty(doc.meta) then
    vim.list_extend(new_lines, serde.encode_frontmatter(doc.meta))
  end
  vim.list_extend(new_lines, doc.body)
  writefile(path, new_lines)
  return doc.meta
end

-- Merge a patch into a scene's YAML block, creating the block if absent.
function M.scene_write(scene, patch)
  local lines = vim.fn.readfile(scene.path)
  if not lines then
    return nil
  end
  local block = serde.parse_scene_block(lines, scene.start_line, scene.end_line or #lines)
  local meta = block.meta or {}
  for k, v in pairs(patch or {}) do
    if v == vim.NIL then
      meta[k] = nil
    else
      meta[k] = v
    end
  end
  if not meta.id then
    meta.id = M.new_id(scene)
  end
  local replacement = serde.encode_scene(meta)
  local first = block.yaml_start or (scene.start_line + 1)
  local last = block.yaml_end or scene.start_line
  for i = last, first, -1 do
    table.remove(lines, i)
  end
  for i = #replacement, 1, -1 do
    table.insert(lines, first, replacement[i])
  end
  writefile(scene.path, lines)
  return meta
end

-- Replace a scene's entire metadata block with `newmeta` (id preserved).
function M.scene_set(scene, newmeta)
  local lines = vim.fn.readfile(scene.path)
  if not lines then
    return nil
  end
  local block = serde.parse_scene_block(lines, scene.start_line, scene.end_line or #lines)
  local meta = vim.tbl_extend("force", { id = block.meta.id or M.new_id(scene) }, newmeta or {})
  local replacement = serde.encode_scene(meta)
  local first = block.yaml_start or (scene.start_line + 1)
  local last = block.yaml_end or scene.start_line
  for i = last, first, -1 do
    table.remove(lines, i)
  end
  for i = #replacement, 1, -1 do
    table.insert(lines, first, replacement[i])
  end
  writefile(scene.path, lines)
  return meta
end

-- Ensure a scene has a stable id, returning it.
function M.ensure_id(scene)
  local lines = vim.fn.readfile(scene.path) or {}
  local block = serde.parse_scene_block(lines, scene.start_line, scene.end_line or #lines)
  if block.meta.id then
    return block.meta.id
  end
  return M.scene_write(scene, {}).id
end

-- Migrate legacy inline `- **Key:** value` bullets directly below a scene
-- heading into a scene YAML block. Returns the number of scenes migrated.
function M.migrate(path)
  local lines = vim.fn.readfile(path)
  if not lines then
    return 0
  end

  local headings = {}
  for i, ln in ipairs(lines) do
    if ln:match("^##%s+") then
      headings[#headings + 1] = i
    end
  end

  local migrated = 0
  for n, start_line in ipairs(headings) do
    local end_line = (headings[n + 1] or (#lines + 1)) - 1
    local block = serde.parse_scene_block(lines, start_line, end_line)
    if not block.yaml_start then
      local inline = read.inline(lines, start_line, end_line)
      if not vim.tbl_isempty(inline) then
        local kept = {}
        for i = 1, start_line do
          kept[#kept + 1] = lines[i]
        end
        vim.list_extend(kept, serde.encode_scene(inline))
        for i = start_line + 1, #lines do
          local line = lines[i]
          if not serde.parse_inline(line) then
            kept[#kept + 1] = line
          end
        end
        lines = kept
        migrated = migrated + 1
      end
    end
  end

  if migrated > 0 then
    writefile(path, lines)
  end
  return migrated
end

-- Route a field write by schema: scene fields go to the scene block, the rest
-- go to chapter frontmatter.
function M.set_field(scene, key, value)
  if schema.is_scene_field(key) and scene then
    return M.scene_write(scene, { [key] = value })
  end
  return M.chapter_write(scene.path, { [key] = value })
end

return M
