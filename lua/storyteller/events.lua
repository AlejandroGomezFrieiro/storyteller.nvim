-- storyteller.events
-- Autocmd wiring: associate buffers with the project, optional detect-on-save.

local project = require("storyteller.project")
local config = require("storyteller.config")

local M = {}

-- Re-resolve project for the buffer so renames/dir changes are picked up.
local function attach(bufnr)
  local file = vim.api.nvim_buf_get_name(bufnr)
  if file == "" or vim.bo[bufnr].buftype ~= "" then
    return
  end
  -- touch the project resolution (caches per-buffer via a separate module)
  vim.b[bufnr].storyteller_project = project.resolve(file)
end

M.setup = function()
  local group = vim.api.nvim_create_augroup("Storyteller", { clear = true })

  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = "markdown",
    callback = function(ev)
      attach(ev.buf)
    end,
  })

  if config.get().detect_on_save then
    vim.api.nvim_create_autocmd("BufWritePost", {
      group = group,
      pattern = "*.md",
      callback = function(ev)
        if not vim.b[ev.buf].storyteller_project then
          return
        end
        -- Deferred to a later phase; detection starts in Phase 3.
        -- `require("storyteller.detect").maybe_auto(ev.buf)` will live here.
      end,
    })
  end
end

return M