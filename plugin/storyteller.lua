-- storyteller (plugin/ entry point)
-- Registers a lightweight `:Story` stub so the command exists for lazy
-- loaders (lazy.nvim's `cmd = "Story"`); the first invocation boots setup()
-- and dispatches immediately.
--
-- plugin/ scripts source AFTER the user's config, so if setup() already ran
-- and registered the real command, this file must not touch it.

if vim.fn.exists(":Story") ~= 0 then
  return
end

vim.api.nvim_create_user_command("Story", function(opts)
  pcall(vim.api.nvim_del_user_command, "Story")
  require("storyteller").setup()
  -- setup() no-ops when already initialized; make sure the real command is
  -- (re-)registered regardless.
  local commands = require("storyteller.commands")
  commands._registered = nil
  commands.setup()
  commands.dispatch(require("storyteller.project").current(), opts.fargs, { bang = opts.bang })
end, {
  nargs = "*",
  bang = true,
  range = true,
  desc = "Storyteller (boots on first use)",
})
