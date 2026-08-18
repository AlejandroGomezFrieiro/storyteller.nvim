-- storyteller.pickers
-- Picker-agnostic interface. The active backend is chosen from config
-- (`picker`), defaulting to telescope when available, else a minimal fallback.
--
-- Contract:
--   pickers.pick(kind, opts)      run a named picker (telescope/fzf builtin)
--   pickers.pick_list(entries, opts)   select from a table of {value, display}
--   pickers.backend()             -> current backend name

local config = require("storyteller.config")

local M = {}

local function has(mod)
  return pcall(require, mod)
end

M.backend = function()
  local cfg = config.get().picker
  if cfg == "telescope" and has "telescope.builtin" then
    return "telescope"
  end
  if cfg == "fzf" and has "fzf-lua" then
    return "fzf"
  end
  if cfg == "minipick" then
    return "minipick"
  end
  -- auto
  if cfg == "auto" then
    if has "telescope.builtin" then
      return "telescope"
    end
    if has "fzf-lua" then
      return "fzf"
    end
  end
  return "fallback"
end

-- `kind` in { "files", "grep", "git_status", "buffers" } passed to the builtin.
-- opts: { prompt_title, cwd, search, glob }
M.pick = function(kind, opts)
  opts = opts or {}
  local backend = M.backend()
  if backend == "telescope" then
    return require("storyteller.pickers.telescope").pick(kind, opts)
  elseif backend == "fzf" then
    return require("storyteller.pickers.fzf").pick(kind, opts)
  end
  return require("storyteller.pickers.fallback").pick(kind, opts)
end

-- Select from prepared entries. Each entry: { value=..., display=... [, hint] }.
-- opts.on_select(entry, action_opt)
M.pick_list = function(entries, opts)
  opts = opts or {}
  local backend = M.backend()
  if backend == "telescope" then
    return require("storyteller.pickers.telescope").pick_list(entries, opts)
  elseif backend == "fzf" then
    return require("storyteller.pickers.fzf").pick_list(entries, opts)
  end
  return require("storyteller.pickers.fallback").pick_list(entries, opts)
end

return M