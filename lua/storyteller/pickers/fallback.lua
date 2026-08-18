-- storyteller.pickers.fallback
-- Minimal pickers using nothing beyond the core nvim API (vim.ui.select).
-- Keeps the plugin usable with zero optional dependencies.

local M = {}

M.pick = function(kind, opts)
  opts = opts or {}
  -- Without a fancy picker, at least reveal the directory (oil-like) or a notify.
  if kind == "files" then
    local dir = opts.cwd or vim.fn.getcwd()
    vim.notify(("Storyteller: open `%s` (install telescope/fzf-lua for a picker)"):format(dir), vim.log.levels.INFO)
    vim.cmd("cd" .. "" .. vim.fn.fnameescape(dir))
  elseif kind == "grep" then
    vim.notify(("Storyteller: grep for `%s` (needs telescope/fzf-lua)"):format(opts.search or ""), vim.log.levels.WARN)
  end
end

M.pick_list = function(entries, opts)
  opts = opts or {}
  local items = {}
  for _, e in ipairs(entries) do
    -- vim.ui.select wants { label = ... }
    local t = { value = e.value, label = e.display or tostring(e.value) }
    table.insert(items, t)
  end
  vim.ui.select(items, { prompt = opts.prompt_title or "Storyteller" }, function(choice)
    if choice and opts.on_select then
      opts.on_select(choice.value, "default")
    end
  end)
end

return M