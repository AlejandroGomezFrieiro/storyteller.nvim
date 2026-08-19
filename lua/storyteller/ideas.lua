-- storyteller.ideas
-- A project-level ideas inbox in `research/ideas.md`. `:Story idea` appends a
-- dated bullet without leaving the buffer; `:Story ideas` opens the inbox.

local project = require("storyteller.project")

local M = {}

function M.path(prj)
  prj = prj or project.current()
  if not prj then
    return nil
  end
  return prj.research .. "/ideas.md"
end

-- Append a new idea bullet. Returns the path.
function M.append(prj, text)
  prj = prj or project.current()
  if not prj then
    vim.notify("[storyteller] Not in a storytelling project.", vim.log.levels.WARN)
    return nil
  end
  local path = M.path(prj)
  vim.fn.mkdir(prj.research, "p")
  local lines = {}
  if vim.loop.fs_stat(path) then
    lines = vim.fn.readfile(path)
  else
    lines = { "# Ideas" }
  end
  lines[#lines + 1] = ("- [ ] %s — %s"):format(os.date("%Y-%m-%d"), text)
  vim.fn.writefile(lines, path)
  return path
end

-- Prompt for an idea and append it.
function M.capture(prj)
  prj = prj or project.current()
  if not prj then
    vim.notify("[storyteller] Not in a storytelling project.", vim.log.levels.WARN)
    return
  end
  vim.ui.input({ prompt = "Idea: " }, function(value)
    if not value or value == "" then
      return
    end
    local path = M.append(prj, value)
    if path then
      vim.notify("[storyteller] Idea captured.", vim.log.levels.INFO)
    end
  end)
end

-- Open the ideas inbox file.
function M.open(prj)
  prj = prj or project.current()
  if not prj then
    vim.notify("[storyteller] Not in a storytelling project.", vim.log.levels.WARN)
    return
  end
  local path = M.path(prj)
  if vim.loop.fs_stat(path) then
    vim.cmd("edit " .. vim.fn.fnameescape(path))
  else
    vim.notify("[storyteller] No ideas yet — capture one with :Story idea.", vim.log.levels.INFO)
  end
end

return M
