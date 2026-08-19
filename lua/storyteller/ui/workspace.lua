-- storyteller.ui.workspace
-- A Scrivener-style three-pane workspace: binder (left), editor (center),
-- inspector (right). `toggle` opens it once and closes it on the next call.

local M = {}

-- prj.root -> { binder = winid, inspector = winid }
local state = {}

function M.open(prj)
  prj = prj or require("storyteller.project").current()
  if not prj then
    vim.notify("[storyteller] Not in a storytelling project.", vim.log.levels.WARN)
    return nil
  end
  local views = require("storyteller.ui.views")

  vim.cmd("leftabove vsplit")
  views.binder(prj)
  local binder_win = vim.api.nvim_get_current_win()

  vim.cmd("wincmd l")
  vim.cmd("rightbelow vsplit")
  local inspector_win = vim.api.nvim_get_current_win()
  if not views.inspector(prj) then
    vim.api.nvim_win_close(inspector_win, true)
    inspector_win = nil
  end

  vim.cmd("wincmd h")
  state[prj.root] = { binder = binder_win, inspector = inspector_win }
  return true
end

function M.close(prj)
  prj = prj or require("storyteller.project").current()
  local st = prj and state[prj.root]
  if not st then
    return
  end
  for _, win in ipairs({ st.inspector, st.binder }) do
    if win and vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end
  state[prj.root] = nil
end

function M.toggle(prj)
  prj = prj or require("storyteller.project").current()
  local st = prj and state[prj.root]
  if st and st.binder and vim.api.nvim_win_is_valid(st.binder) then
    M.close(prj)
  else
    M.open(prj)
  end
end

return M
