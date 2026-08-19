-- Minimal deterministic setup used by docs/vhs/*.tape.
-- Records the plugin surface AND the storyteller LSP (hover, gd, gr,
-- completion, code actions, diagnostics) on the small project in demo/.
vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.g.mapleader = " "
vim.o.termguicolors = true
vim.cmd("colorscheme habamax")
vim.o.mousemodel = "extend"
vim.o.swapfile = false

require("storyteller").setup({
  autocmds = false,
  detect_on_save = false,
  picker = "auto",
})

if vim.lsp.config then
  vim.lsp.config("storyteller", {
    cmd = { "storyteller-lsp" },
    filetypes = { "markdown" },
    root_markers = { ".storyteller", ".git" },
  })
  vim.lsp.enable("storyteller")
  -- Deterministic attach: VHS opens the chapter before the LSP client can
  -- auto-start, so we start it ourselves on VimEnter for the markdown buffer
  -- under a .storyteller root.
  vim.api.nvim_create_autocmd("VimEnter", {
    callback = function()
      vim.schedule(function()
        local buf = vim.api.nvim_get_current_buf()
        local name = vim.fn.bufname(buf)
        if name:sub(-3) ~= ".md" then
          return
        end
        vim.bo[buf].filetype = "markdown"
        if vim.lsp.get_clients({ bufnr = buf })[1] then
          return
        end
        local marker = vim.fs.find(".storyteller", {
          upward = true,
          path = vim.fn.getcwd(),
        })
        if #marker == 0 then
          marker = vim.fs.find(".storyteller", {
            upward = true,
            path = name,
          })
        end
        if #marker == 0 then
          return
        end
        pcall(vim.lsp.start, {
          name = "storyteller",
          cmd = { "storyteller-lsp" },
          root_dir = vim.fs.dirname(marker[1]),
        })
      end)
    end,
  })
end

-- Record the writing-profile keymaps so the tapes show the real surface.
local function buf_map(mode, lhs, rhs)
  vim.keymap.set(mode, lhs, rhs, { buffer = true, nowait = true })
end
local function code_action_filtered(title_pat)
  local opts = {
    filter = function(action)
      return action.title:find(title_pat) ~= nil
    end,
  }
  pcall(vim.lsp.buf.code_action, opts)
end
vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(args)
    local client = vim.lsp.get_client_by_id(args.data.client_id)
    if client and client.name == "storyteller" then
      buf_map("n", "K", vim.lsp.buf.hover)
      buf_map("n", "gd", vim.lsp.buf.definition)
      buf_map("n", "gr", vim.lsp.buf.references)
      buf_map("n", "<leader>lr", vim.lsp.buf.rename)
      buf_map("n", "<leader>o", vim.lsp.buf.document_symbol)
      buf_map("n", "<leader>la", vim.lsp.buf.code_action)
      buf_map("n", "<leader>lc", function()
        code_action_filtered("Create Creatures card")
      end)
      buf_map("v", "<leader>lc", function()
        code_action_filtered("Create Creatures card")
      end)
      buf_map("n", "<leader>ll", function()
        code_action_filtered("Link")
      end)
      buf_map("v", "<leader>ll", function()
        code_action_filtered("Link")
      end)
      vim.bo[args.buf].omnifunc = "v:lua.vim.lsp.omnifunc"
    end
  end,
})