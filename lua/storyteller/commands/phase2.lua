-- storyteller.commands.phase2
-- Phase 2 commands: Scrivenings, Collection filter, saved Collections, and the
-- frontmatter Meta editor.

local project = require("storyteller.project")
local metadata = require("storyteller.metadata")
local command = require("storyteller.command")
local scrivenings = require("storyteller.scrivenings")
local collections = require("storyteller.collections")

local M = {}

local function current_prj()
  local prj = project.current()
  if not prj then
    vim.notify("[storyteller] Not in a storytelling project.", vim.log.levels.WARN)
    return nil
  end
  return prj
end

-- --- Frontmatter (Meta) scratch editor --------------------------------

local function save_meta(buf)
  local st = vim.b[buf].storyteller_meta
  if not st then
    return
  end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local parsed = metadata.parse_block(lines)
  if not parsed then
    vim.notify(
      "[storyteller] Meta: could not parse frontmatter, nothing written.",
      vim.log.levels.ERROR
    )
    return
  end
  -- Rebuild the doc: keep the body captured at open, frontmatter from the
  -- (possibly edited) scratch buffer.
  metadata.write({
    path = st.path,
    meta = parsed.meta,
    frontmatter = lines,
    body = st.body,
    had_block = true,
  })
  vim.bo[buf].modified = false
  vim.notify(
    ("[storyteller] Meta written to %s."):format(vim.fn.fnamemodify(st.path, ":t")),
    vim.log.levels.INFO
  )
end

local function open_meta()
  local path = vim.fn.expand("%:p")
  if path == "" or vim.fn.filereadable(path) ~= 1 then
    vim.notify("[storyteller] No file to edit frontmatter for.", vim.log.levels.WARN)
    return
  end
  local doc = metadata.read(path)
  if not doc then
    return
  end
  local buf = vim.api.nvim_create_buf(false, false)
  vim.api.nvim_buf_set_name(buf, "storyteller://meta/" .. vim.fn.fnamemodify(path, ":t"))
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, doc.frontmatter or metadata.encode(doc.meta))
  vim.bo[buf].buftype = "acwrite"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "yaml"
  vim.b[buf].storyteller_meta = { path = path, body = doc.body }
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = buf,
    callback = function(ev)
      save_meta(ev.buf)
    end,
  })
  vim.api.nvim_set_current_buf(buf)
end

M.setup = function()
  -- Scrivenings is registered by its own module (incl. the `!` rebuild); the
  -- entry below routes through the same command registry for cohesion.
  scrivenings.setup()

  -- Saved-filter picker: predicate -> value -> matching scene.
  command.register("Collection", function(_)
    collections.pick(current_prj())
  end, { desc = "Pick a saved filter (pov/status/...) then a scene", opts = { nargs = 0 } })

  -- The add-to-named-list and list-saved commands live in collections.setup.
  collections.setup()

  -- Frontmatter scratch editor for the current file.
  command.register("Meta", function(_)
    open_meta()
  end, { desc = "Edit frontmatter in a scratch buffer (`:w` writes)", opts = { nargs = 0 } })
end

return M
