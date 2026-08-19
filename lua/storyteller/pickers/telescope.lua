-- storyteller.pickers.telescope
-- Telescope-backed pickers (used when telescope.nvim is available).

local M = {}

local function require_ok(mod)
  local ok, mod = pcall(require, mod)
  if not ok then
    return nil
  end
  return mod
end

-- Convert a kind into a telescope builtin callable.
local BUILTIN = {
  files = function(tb, opts)
    tb.find_files({ prompt_title = opts.prompt_title or "Storyteller files", cwd = opts.cwd })
  end,
  grep = function(tb, opts)
    tb.grep_string({
      prompt_title = opts.prompt_title or "Storyteller grep",
      cwd = opts.cwd,
      search = opts.search or "",
    })
  end,
  buffers = function(tb, opts)
    tb.buffers({ prompt_title = opts.prompt_title or "Buffers" })
  end,
}

M.pick = function(kind, opts)
  opts = opts or {}
  local tb = require_ok "telescope.builtin"
  if not tb then
    return
  end
  local fn = BUILTIN[kind]
  if fn then
    fn(tb, opts)
  end
end

M.pick_list = function(entries, opts)
  opts = opts or {}
  local presenters = require_ok "telescope.pickers"
  local finders = require_ok "telescope.finders"
  local sorters = require_ok "telescope.sorters"
  local actions = require_ok "telescope.actions"
  local state = require_ok "telescope.actions.state"

  if not (presenters and finders and sorters and actions and state) then
    return require("storyteller.pickers.fallback").pick_list(entries, opts)
  end

  local results = {}
  for _, e in ipairs(entries) do
    results[#results + 1] = { value = e.value, display = e.display or tostring(e.value) }
  end

  presenters.new(opts.bufnr or vim.api.nvim_get_current_buf(), {
    prompt_title = opts.prompt_title or "Storyteller",
    results_title = opts.results_title,
    finder = finders.new_table({ results = results }),
    sorter = sorters.get_generic_fuzzy_sorter({}),
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        local entry = state.get_selected_entry()
        actions.close(prompt_bufnr)
        if entry then
          local action = vim.g.storyteller_last_action or "default"
          if opts.on_select then
            opts.on_select(entry.value, action)
          end
        end
      end)
      return true
    end,
  }):find()
end

return M