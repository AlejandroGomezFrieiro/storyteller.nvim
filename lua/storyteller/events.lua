-- storyteller.events
-- Autocmd wiring: associate buffers with the project, remember the last scene,
-- and (optionally) auto-detect references on save.

local project = require("storyteller.project")
local config = require("storyteller.config")
local resume = require("storyteller.resume")
local schema = require("storyteller.schema")

local M = {}

local function attach(bufnr)
  local file = vim.api.nvim_buf_get_name(bufnr)
  if file == "" or vim.bo[bufnr].buftype ~= "" then
    return
  end
  vim.b[bufnr].storyteller_project = project.resolve(file)
  -- Re-apply this project's merged schema so multiple open projects don't
  -- fight over the module-global vocabulary (cached per root, cheap).
  local prj = vim.b[bufnr].storyteller_project
  if prj then
    schema.load(prj.root)
  end
end

M.setup = function()
  local group = vim.api.nvim_create_augroup("Storyteller", { clear = true })

  vim.api.nvim_create_autocmd({ "FileType", "BufEnter" }, {
    group = group,
    pattern = "markdown",
    callback = function(ev)
      if not vim.b[ev.buf].storyteller_project then
        attach(ev.buf)
      end
    end,
  })

  -- Buffers opened before setup() never saw FileType=markdown; catch them here.
  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    callback = function(ev)
      if
        vim.b[ev.buf].storyteller_project == nil
        and ev.buf == vim.api.nvim_get_current_buf()
        and vim.bo[ev.buf].filetype == "markdown"
      then
        attach(ev.buf)
      end
    end,
  })

  vim.api.nvim_create_autocmd("BufLeave", {
    callback = function(ev)
      if vim.b[ev.buf].storyteller_project then
        resume.remember(vim.b[ev.buf].storyteller_project)
      end
    end,
  })

  -- Invalidate the cached merged schema when a schema source is written.
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    pattern = { "schema.json", "storyteller.schema.json", ".storyteller.toml" },
    callback = function(ev)
      local prj = project.resolve(vim.api.nvim_buf_get_name(ev.buf))
      if prj then
        schema.invalidate(prj.root)
      end
    end,
  })

  -- Reactive views: any open storyteller view refreshes when a project file
  -- is saved, so outline/corkboard/tracking never show stale numbers.
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    pattern = "*.md",
    callback = function()
      vim.schedule(function()
        for _, b in ipairs(vim.fn.getbufinfo({ bufloaded = 1 })) do
          if b.changed == 0 then
            local fn = vim.b[b.bufnr].storyteller_refresh
            if fn then
              pcall(fn)
            end
          end
        end
      end)
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
              if
                sc.path == file
                and sc.start_line <= line
                and line <= (sc.end_line or math.huge)
              then
                local n = detect.link_all(sc, prj)
                if n > 0 then
                  vim.notify(
                    ("[storyteller] Auto-linked %d reference(s) in this scene."):format(n),
                    vim.log.levels.INFO
                  )
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
