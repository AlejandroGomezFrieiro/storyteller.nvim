-- Storyteller — runtimepath entry.
-- <plugin readme note: this file is sourced on plugin load; work is deferred
--  to `require("storyteller").setup()`.>
vim.schedule(function()
  require("storyteller").setup()
end)