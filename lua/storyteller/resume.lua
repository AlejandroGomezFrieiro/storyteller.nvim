-- storyteller.resume
-- Remember and return to the last visited scene, keyed by project root.

local index = require("storyteller.index")
local project = require("storyteller.project")
local meta = require("storyteller.meta")

local M = {}

local function path(prj)
  local dir = vim.fn.stdpath("state") .. "/storyteller"
  vim.fn.mkdir(dir, "p")
  return dir .. "/" .. vim.fn.sha256(prj.root):sub(1, 12) .. ".json"
end

function M.remember(prj)
  prj = prj or project.current()
  local scene = prj and index.current_scene(prj)
  if not scene then
    return
  end
  local data = {
    path = scene.path,
    id = meta.scene(scene).meta.id,
    line = vim.api.nvim_win_get_cursor(0)[1],
  }
  vim.fn.writefile({ vim.json.encode(data) }, path(prj))
end

function M.open(prj)
  prj = prj or project.current()
  if not prj or vim.fn.filereadable(path(prj)) ~= 1 then
    return
  end
  local ok, saved = pcall(vim.json.decode, table.concat(vim.fn.readfile(path(prj)), "\n"))
  if not ok then
    return
  end
  for _, scene in ipairs(index.scenes(prj)) do
    local id = meta.scene(scene).meta.id
    if (saved.id and id == saved.id) or (not saved.id and scene.path == saved.path) then
      vim.cmd("edit " .. vim.fn.fnameescape(scene.path))
      vim.api.nvim_win_set_cursor(0, { math.max(scene.start_line, saved.line or scene.start_line), 0 })
      return scene
    end
  end
end

return M
