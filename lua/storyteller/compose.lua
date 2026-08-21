-- storyteller.compose
-- Distraction-free composition mode: the current buffer goes fullscreen in a
-- centered column over a dimmed backdrop. Editing works exactly as before;
-- <Esc>/q (in normal mode) or the toggle key restores your layout.

local M = {}

local state = nil

local function close()
  if not state then
    return
  end
  for _, win in ipairs(state.wins or {}) do
    if vim.api.nvim_win_is_valid(win) then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_set_current_win(state.win)
  end
  pcall(vim.keymap.del, "n", "<Esc>", { buffer = state.buf })
  if state.mapped_q then
    pcall(vim.keymap.del, "n", "q", { buffer = state.buf })
  end
  state = nil
end

function M.active()
  return state ~= nil
end

function M.toggle(width)
  if state then
    close()
    return
  end
  local buf = vim.api.nvim_get_current_buf()
  if vim.bo[buf].buftype ~= "" then
    vim.notify("[storyteller] Composition mode is for real buffers.", vim.log.levels.WARN)
    return
  end

  width = math.min(width or 96, vim.o.columns - 8)
  local height = vim.o.lines - 4
  local backdrop = vim.api.nvim_open_win(buf, false, {
    relative = "editor",
    row = 0,
    col = 0,
    width = vim.o.columns,
    height = vim.o.lines - vim.opt.cmdheight:get() - 1,
    style = "minimal",
    zindex = 40,
  })
  vim.wo[backdrop].winhighlight = "Normal:StorytellerComposeBackdrop"
  local main = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = 1,
    col = math.floor((vim.o.columns - width) / 2),
    width = width,
    height = height,
    style = "minimal",
    zindex = 50,
  })
  vim.wo[main].wrap = true
  vim.wo[main].linebreak = true
  vim.wo[main].number = false
  vim.wo[main].relativenumber = false
  vim.wo[main].signcolumn = "no"
  vim.wo[main].foldcolumn = "0"
  vim.wo[main].cursorline = false
  vim.wo[main].spell = true
  vim.wo[main].winhighlight = "Normal:StorytellerCompose"
  vim.wo[main].colorcolumn = ""

  state = { wins = { backdrop, main }, buf = buf }
  vim.keymap.set(
    "n",
    "<Esc>",
    close,
    { buffer = buf, silent = true, desc = "Leave composition mode" }
  )
  -- Only hijack `q` when the buffer is a storyteller view (where q closes);
  -- prose buffers keep macro recording.
  if vim.bo[buf].filetype:match("^storyteller%-") or vim.bo[buf].buftype == "nofile" then
    vim.keymap.set(
      "n",
      "q",
      close,
      { buffer = buf, silent = true, desc = "Leave composition mode" }
    )
    state.mapped_q = true
  end
end

-- Palette entry used by :Story compose.
M.toggle_fn = M.toggle

return M
