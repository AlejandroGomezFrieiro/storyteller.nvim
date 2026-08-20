-- Minimal deterministic setup used by docs/vhs/*.tape.
-- Records the plugin surface AND the storyteller LSP (hover, gd, gr,
-- completion, code actions, diagnostics) on the small project in demo/.
vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.g.mapleader = " "
vim.o.termguicolors = true
vim.o.background = "dark"
pcall(vim.cmd, "colorscheme lunaperche")
vim.o.mousemodel = "extend"
vim.o.swapfile = false

-- Keep the editor and VHS frame in the same quiet, nocturnal palette.
local highlights = {
  Normal = { fg = "#c6d0f5", bg = "#303446" },
  NormalFloat = { fg = "#c6d0f5", bg = "#292c3c" },
  FloatBorder = { fg = "#8caaee", bg = "#292c3c" },
  FloatTitle = { fg = "#f2d5cf", bg = "#292c3c", bold = true },
  CursorLine = { bg = "#414559" },
  Visual = { bg = "#626880" },
  Pmenu = { fg = "#c6d0f5", bg = "#292c3c" },
  PmenuSel = { fg = "#303446", bg = "#8caaee" },
  StatusLine = { fg = "#c6d0f5", bg = "#414559" },
  WinSeparator = { fg = "#626880", bg = "#303446" },
}
for name, value in pairs(highlights) do
  vim.api.nvim_set_hl(0, name, value)
end

-- Use the richer LSP presentation in the demo shell when it is available.
local has_lspsaga = pcall(function()
  require("lspsaga").setup({})
end)
local has_blink = pcall(function()
  require("blink.cmp").setup({
    keymap = { preset = "default" },
    completion = {
      menu = { border = "rounded" },
      documentation = { auto_show = true, auto_show_delay_ms = 250 },
    },
    sources = { default = { "lsp", "path", "snippets", "buffer" } },
  })
end)

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
local function code_action()
  if has_lspsaga then
    vim.cmd("Lspsaga code_action")
  else
    code_action_filtered("Create Creatures card")
  end
end
vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(args)
    local client = vim.lsp.get_client_by_id(args.data.client_id)
    if client and client.name == "storyteller" then
      if has_lspsaga then
        buf_map("n", "K", function()
          vim.cmd("Lspsaga hover_doc")
        end)
        buf_map("n", "gd", function()
          vim.cmd("Lspsaga goto_definition")
        end)
        buf_map("n", "gr", function()
          vim.cmd("Lspsaga finder ref")
        end)
        buf_map("n", "<leader>la", function()
          vim.cmd("Lspsaga code_action")
        end)
      else
        buf_map("n", "K", vim.lsp.buf.hover)
        buf_map("n", "gd", vim.lsp.buf.definition)
        buf_map("n", "gr", vim.lsp.buf.references)
      end
      buf_map("n", "<leader>lr", vim.lsp.buf.rename)
      buf_map("n", "<leader>o", vim.lsp.buf.document_symbol)
      if not has_lspsaga then
        buf_map("n", "<leader>la", vim.lsp.buf.code_action)
      end
      buf_map("n", "<leader>lc", function()
        code_action()
      end)
      buf_map("v", "<leader>lc", function()
        code_action()
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
