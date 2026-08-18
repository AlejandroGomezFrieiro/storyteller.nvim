-- Minimal deterministic setup used by docs/vhs/*.tape.
vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.g.mapleader = " "
vim.o.termguicolors = true
vim.cmd("colorscheme habamax")
require("storyteller").setup({
  autocmds = false,
  detect_on_save = false,
  picker = "auto",
})
