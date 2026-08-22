-- storyteller.capture
-- Create a reference card from a visual selection (or the word under the
-- cursor). This is the plugin-side implementation; when a Storyteller LSP is
-- attached, `commands.lua` may delegate card generation to the server instead.

local project = require("storyteller.project")
local schema = require("storyteller.schema")

local M = {}

local function slugify(s)
  s = (s or ""):lower()
  s = s:gsub("[^%w%s-]", "")
  s = s:gsub("%s+", "-")
  s = s:gsub("%-+", "-")
  return s:gsub("^-", ""):gsub("-$", "")
end

-- All available type folders for this project: schema-declared + discovered.
local function type_dirs(prj)
  local dirs = {}
  if prj and vim.fn.isdirectory(prj.references) == 1 then
    for _, sub in ipairs(vim.fn.glob(prj.references .. "/*", false, true)) do
      if vim.fn.isdirectory(sub) == 1 then
        dirs[#dirs + 1] = vim.fn.fnamemodify(sub, ":t")
      end
    end
  end
  return schema.type_dirs(dirs)
end

-- Accept either a folder ("characters") or a singular schema id ("character").
local function resolve_type(arg, prj)
  if not arg or arg == "" then
    return nil
  end
  for id, t in pairs(schema.reference_types) do
    if id == arg or t.dir == arg then
      return t.dir
    end
  end
  return arg
end

-- Card content, by type folder. Mirrors the shared schema.json templates;
-- a type with `"style": "headings"` gets `### Key` sections instead of
-- `- **Key:**` bullets (reading is style-agnostic either way).
function M.card_lines(ftype, name)
  local body = {}
  local labels = {}
  for _, label in ipairs(schema.type_body(ftype)) do
    labels[#labels + 1] = label
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
  if schema.type_style(ftype) == "headings" then
    for i, label in ipairs(labels) do
      if i > 1 then
        lines[#lines + 1] = ""
      end
      lines[#lines + 1] = "### " .. label
      lines[#lines + 1] = ""
    end
    while lines[#lines] == "" do
      table.remove(lines)
    end
    lines[#lines + 1] = ""
  else
    for _, label in ipairs(labels) do
      body[#body + 1] = "- **" .. label .. ":** "
    end
    vim.list_extend(lines, body)
  end
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

-- Create a card for `name` of type `ftype` (a folder, e.g. "characters").
-- Returns the file path, or nil if it already existed.
function M.create(prj, ftype, name)
  prj = prj or project.current()
  if not prj then
    vim.notify("[storyteller] Not in a storytelling project.", vim.log.levels.WARN)
    return nil
  end
  local dir = prj[ftype] or (prj.references .. "/" .. ftype)
  vim.fn.mkdir(dir, "p")
  local path = dir .. "/" .. slugify(name) .. ".md"
  if vim.loop.fs_stat(path) then
    vim.notify(("[storyteller] Card already exists: %s"):format(path), vim.log.levels.INFO)
    return path
  end
  vim.fn.writefile(M.card_lines(ftype, name), path)
  vim.notify(
    ("[storyteller] Created %s card: %s"):format(schema.type_label(ftype), path),
    vim.log.levels.INFO
  )
  return path
end

-- Pick a type via the picker, then run the full flow.
function M.run(prj, type_arg)
  local name = M.selection()
  if not name then
    vim.notify("[storyteller] Select text or place the cursor on a name.", vim.log.levels.WARN)
    return
  end
  if type_arg and type_arg ~= "" then
    local path = M.create(prj, resolve_type(type_arg, prj), name)
    if path then
      vim.cmd("edit " .. vim.fn.fnameescape(path))
    end
    return
  end
  local pickers = require("storyteller.pickers")
  local entries = {}
  for _, t in ipairs(type_dirs(prj)) do
    entries[#entries + 1] = { value = t, display = schema.type_label(t) }
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

M.types = function(prj)
  local out = {}
  for _, t in ipairs(type_dirs(prj or project.current())) do
    out[t] = { dir = t, label = schema.type_label(t) }
  end
  return out
end

return M
