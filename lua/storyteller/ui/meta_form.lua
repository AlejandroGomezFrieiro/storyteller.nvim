-- storyteller.ui.meta_form
-- Edit a scene's metadata in a scratch buffer (custom buffer, not floating).
-- `:w` re-parses the field list and writes it back to the scene YAML block.

local meta = require("storyteller.meta")
local schema = require("storyteller.schema")
local serde = require("storyteller.meta.serde")

local M = {}

function M.edit(scene)
  if not scene then
    vim.notify("[storyteller] No scene to edit.", vim.log.levels.WARN)
    return nil
  end
  local info = meta.scene(scene)
  -- Present the managed fields only; the stable id is kept out of reach.
  local editable = {}
  for key, value in pairs(info.meta) do
    if key ~= "id" then
      editable[key] = value
    end
  end

  local buf = vim.api.nvim_create_buf(false, false)
  local slug = (scene.title or "scene"):gsub("[^%w]+", "_")
  vim.api.nvim_buf_set_name(buf, "storyteller://meta/" .. slug)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, serde.encode_map(editable, schema.scene_fields))
  vim.bo[buf].buftype = "acwrite"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "yaml"
  vim.b[buf].storyteller_meta_scene = scene

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = buf,
    callback = function(ev)
      local sc = vim.b[ev.buf].storyteller_meta_scene
      if not sc then
        return
      end
      local content = vim.api.nvim_buf_get_lines(ev.buf, 0, -1, false)
      local newmeta = serde.parse_map(content)
      meta.scene_set(sc, newmeta)
      vim.bo[ev.buf].modified = false
      vim.notify("[storyteller] Scene metadata written.", vim.log.levels.INFO)
    end,
  })

  vim.api.nvim_set_current_buf(buf)
  return buf
end

return M
