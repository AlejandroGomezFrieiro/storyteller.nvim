-- storyteller.capture
-- Create a reference card from a visual selection (or the word under the
-- cursor). This is the plugin-side implementation; when a Storyteller LSP is
-- attached, `commands.lua` may delegate card generation to the server instead.

local project = require("storyteller.project")

local M = {}

local TYPES = {
  character = { dir = "characters", label = "Character" },
  location = { dir = "locations", label = "Location" },
  item = { dir = "items", label = "Item" },
  organization = { dir = "organizations", label = "Organization" },
}

local function slugify(s)
  s = (s or ""):lower()
  s = s:gsub("[^%w%s-]", "")
  s = s:gsub("%s+", "-")
  s = s:gsub("%-+", "-")
  return s:gsub("^-", ""):gsub("-$", "")
end

-- Card content, by type. Mirrors the shared schema.json card templates.
function M.card_lines(ftype, name)
  local name = name
  local body = {}
  if ftype == "character" then
    body = { "- **Role:** ", "- **Notes:** " }
  elseif ftype == "location" then
    body = { "- **Atmosphere:** ", "- **Notes:** " }
  elseif ftype == "item" then
    body = { "- **Type:** ", "- **Notes:** " }
  else -- organization
    body = { "- **Wants:** ", "- **Members:** ", "- **Notes:** " }
  end
  local lines = {
    "---",
    "names:",
    "  - " .. name,
    "---",
    "",
    "## " .. name,
    "",
  }
  vim.list_extend(lines, body)
  return lines
end

-- Read the current visual selection, or the word under the cursor.
function M.selection()
  local start = vim.fn.getpos("'<")
  local finish = vim.fn.getpos("'>")
  if start[2] == 0 or finish[2] == 0 then
    return nil
  end
  local srow, scol = start[2] - 1, math.max(0, start[3] - 1)
  local erow, ecol = finish[2] - 1, math.max(0, finish[3] - 1)
  local ok, lines = pcall(vim.api.nvim_buf_get_text, 0, srow, scol, erow, ecol, {})
  if not ok then
    return nil
  end
  local text = table.concat(lines, "\n")
  text = text:gsub("^%s+", ""):gsub("%s+$", "")
  if text == "" then
    text = vim.fn.expand("<cword>")
  end
  text = text:gsub("^%s+", ""):gsub("%s+$", "")
  return text ~= "" and text or nil
end

-- Create a card for `name` of type `ftype`. Returns the file path, or nil if
-- it already existed.
function M.create(prj, ftype, name)
  prj = prj or project.current()
  if not prj then
    vim.notify("[storyteller] Not in a storytelling project.", vim.log.levels.WARN)
    return nil
  end
  local type = TYPES[ftype]
  if not type then
    vim.notify(("[storyteller] Unknown reference type: %s"):format(tostring(ftype)), vim.log.levels.ERROR)
    return nil
  end
  local dir = prj[type.dir] or (prj.references .. "/" .. type.dir)
  vim.fn.mkdir(dir, "p")
  local path = dir .. "/" .. slugify(name) .. ".md"
  if vim.loop.fs_stat(path) then
    vim.notify(("[storyteller] Card already exists: %s"):format(path), vim.log.levels.INFO)
    return path
  end
  vim.fn.writefile(M.card_lines(ftype, name), path)
  vim.notify(("[storyteller] Created %s card: %s"):format(type.label, path), vim.log.levels.INFO)
  return path
end

-- Pick a type via the picker, then run the full flow.
function M.run(prj, type_arg)
  local name = M.selection()
  if not name then
    vim.notify("[storyteller] Select text or place the cursor on a name.", vim.log.levels.WARN)
    return
  end
  if type_arg and TYPES[type_arg] then
    local path = M.create(prj, type_arg, name)
    if path then
      vim.cmd("edit " .. vim.fn.fnameescape(path))
    end
    return
  end
  local pickers = require("storyteller.pickers")
  local entries = {}
  for key, t in pairs(TYPES) do
    entries[#entries + 1] = { value = key, display = t.label }
  end
  table.sort(entries, function(a, b)
    return a.value < b.value
  end)
  pickers.pick_list(entries, {
    prompt_title = "Reference type",
    on_select = function(ftype)
      local path = M.create(prj, ftype, name)
      if path then
        vim.cmd("edit " .. vim.fn.fnameescape(path))
      end
    end,
  })
end

M.types = TYPES

return M
