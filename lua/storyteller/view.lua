-- storyteller.view
-- Shared lifecycle, highlighting, and keymap conventions for derived views.

local M = {}
local buffers = {}

local function key(name, root)
  return name .. "\0" .. root
end

function M.highlights()
  local set = vim.api.nvim_set_hl
  set(0, "StorytellerTitle", { link = "Title", default = true })
  set(0, "StorytellerSection", { link = "Special", default = true })
  set(0, "StorytellerScene", { link = "Identifier", default = true })
  set(0, "StorytellerMuted", { link = "Comment", default = true })
  set(0, "StorytellerMetric", { link = "Number", default = true })
  set(0, "StorytellerDraft", { link = "String", default = true })
  set(0, "StorytellerRevision", { link = "WarningMsg", default = true })
  set(0, "StorytellerDone", { link = "DiagnosticOk", default = true })
  set(0, "StorytellerUnused", { link = "DiagnosticError", default = true })
end

function M.open(name, prj, opts)
  opts = opts or {}
  local id = key(name, prj.root)
  local buf = buffers[id]
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then
    buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, "storyteller://" .. name .. "/" .. vim.fn.fnamemodify(prj.root, ":t"))
    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].swapfile = false
    vim.bo[buf].modifiable = false
    vim.bo[buf].filetype = "storyteller-" .. name
    vim.b[buf].storyteller_project = prj
    buffers[id] = buf
    vim.api.nvim_create_autocmd("BufWipeout", {
      buffer = buf,
      once = true,
      callback = function()
        buffers[id] = nil
      end,
    })
    vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf, silent = true, desc = "Close Storyteller view" })
    vim.keymap.set("n", "?", function()
      vim.notify("<CR> open · R refresh · q close", vim.log.levels.INFO)
    end, { buffer = buf, silent = true, desc = "Storyteller view help" })
  end
  vim.api.nvim_set_current_buf(buf)
  vim.b[buf].storyteller_project = prj
  vim.wo.number = false
  vim.wo.relativenumber = false
  vim.wo.signcolumn = "no"
  vim.wo.foldcolumn = "0"
  vim.wo.cursorline = true
  vim.wo.wrap = false
  vim.wo.spell = false
  vim.wo.winbar = " Storyteller · " .. name .. " · " .. vim.fn.fnamemodify(prj.root, ":t")
  M.highlights()
  return buf
end

function M.render(buf, lines)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
end

return M
