-- storyteller.events
-- Autocmd wiring: associate buffers with the project, optional detect-on-save,
-- live outline word counts.

local project = require("storyteller.project")
local config = require("storyteller.config")
local outline = require("storyteller.outline")
local resume = require("storyteller.resume")

local M = {}

-- Re-resolve project for the buffer so renames/dir changes are picked up.
local function attach(bufnr)
  local file = vim.api.nvim_buf_get_name(bufnr)
  if file == "" or vim.bo[bufnr].buftype ~= "" then
    return
  end
  -- touch the project resolution (caches per-buffer via a separate module)
  vim.b[bufnr].storyteller_project = project.resolve(file)
  -- live word counts on markdown headings
  if vim.bo[bufnr].ft == "markdown" then
    outline.setup_buffer(bufnr)
  end
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

  vim.api.nvim_create_autocmd("BufLeave", {
    group = group,
    pattern = "*.md",
    callback = function(ev)
      if vim.b[ev.buf].storyteller_project then
        resume.remember(vim.b[ev.buf].storyteller_project)
      end
    end,
  })

  if config.get().detect_on_save then
    local debounce = config.get().detect_debounce or 300
    local timers = {}
    vim.api.nvim_create_autocmd("BufWritePost", {
      group = group,
      pattern = "*.md",
      callback = function(ev)
        if not vim.b[ev.buf].storyteller_project then
          return
        end
        -- Debounced auto-detect for the scene just saved: auto-link confident
        -- matches (confidence >= 0.9), the conservative Kindling-style default.
        -- Capture this write's location before the debounce timer runs. The
        -- user may move to a different scene or buffer before it fires.
        local line = vim.api.nvim_win_get_cursor(0)[1]
        if timers[ev.buf] then
          vim.fn.timer_stop(timers[ev.buf])
        end
        timers[ev.buf] = vim.fn.timer_start(debounce, function()
          local ok, err = pcall(function()
            local detect = require("storyteller.detect")
            local index = require("storyteller.index")
            local prj = vim.b[ev.buf].storyteller_project
            local file = vim.api.nvim_buf_get_name(ev.buf)
            for _, sc in ipairs(index.scenes(prj)) do
              if sc.path == file and sc.start_line <= line and line <= (sc.end_line or math.huge) then
                local n = detect.link_all(sc, prj)
                if n > 0 then
                  vim.notify(("[storyteller] Auto-linked %d reference(s) in this scene."):format(n), vim.log.levels.INFO)
                end
                return
              end
            end
          end)
          if not ok then
            vim.notify("[storyteller] auto-detect failed: " .. tostring(err), vim.log.levels.ERROR)
          end
          timers[ev.buf] = nil
        end)
      end,
    })
  end
end

return M
