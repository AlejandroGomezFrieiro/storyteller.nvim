-- storyteller.command
-- Central user-command registry for the `:Story*` namespace.
-- Later phases register handlers via `command.register(name, fn, opts)`;
-- `setup()` materializes them once as `:Story<Name>`.

local M = {}

-- name -> { fn = function(args), desc = string, opts = table }
local registry = {}

-- Register (or replace) a command handler.
--   name: "Outline" -> creates `:StoryOutline`
--   args: { fargs = {...} } vim user command args, count, ...
M.register = function(name, fn, opts)
  registry[name] = vim.tbl_extend("force", { fn = fn, desc = name, opts = {} }, opts or {})
end

-- Delete/disable a command.
M.unregister = function(name)
  registry[name] = nil
end

M.list = function()
  return registry
end

M.setup = function()
  local defined = {}
  for name, entry in pairs(registry) do
    if not defined[name] then
      vim.api.nvim_create_user_command("Story" .. name, entry.fn, vim.tbl_extend("force", {}, entry.opts))
      defined[name] = true
    end
  end
end

return M