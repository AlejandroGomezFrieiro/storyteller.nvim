-- storyteller.import
-- Migration helpers: Scrivener .scrivx project import (best effort) and
-- Fountain export of the manuscript.
--
-- Scrivener import: a .scrivx file is XML describing the binder. We walk
-- BinderItem entries, read each text document's RTF from the .scriv folder,
-- strip formatting crud, and lay the result out as chapters/*.md with ## scenes.
--
-- Fountain export: metadata-free manuscript mapped to plain Fountain —
--   "# Chapter"  -> chapter heading stays a markdown-style heading? No:
--   chapters become `# Title` section headings; `## Scene` becomes a forced
--   scene heading ".Title" so Fountain-aware apps treat it as a slugline.

local project = require("storyteller.project")
local index = require("storyteller.index")
local compile = require("storyteller.compile")

local M = {}

local function join(...)
  return table.concat({ ... }, "/")
end

local function slugify(name)
  local s = name:lower():gsub("[^%w%s%-]", ""):gsub("%s+", "-"):gsub("^-+", ""):gsub("-+$", "")
  return s ~= "" and s or "untitled"
end

-- --- RTF -> text (best effort) ----------------------------------------------

-- A tiny RTF walker: tracks brace depth, skips destination groups (fonttbl,
-- colortbl, stylesheet, info, pict), turns \par/\line into newlines, decodes
-- \'hh hex escapes, and drops every other control word. Good enough for prose
-- drafts exported by Scrivener; not a real parser.
function M.rtf_to_text(rtf)
  local text = {}
  local i, n = 1, #(rtf or "")
  local depth = 0
  local skip_below = nil -- discard content while depth > skip_below
  while i <= n do
    local c = rtf:sub(i, i)
    if c == "{" then
      depth = depth + 1
      if not skip_below then
        local dest = rtf:match("^\\(%a+)", i + 1)
        if
          dest == "fonttbl"
          or dest == "colortbl"
          or dest == "stylesheet"
          or dest == "info"
          or dest == "pict"
        then
          skip_below = depth
        end
      end
      i = i + 1
    elseif c == "}" then
      if skip_below and depth <= skip_below then
        skip_below = nil
      end
      depth = depth - 1
      i = i + 1
    elseif c == "\\" then
      if skip_below then
        -- consume the control word but emit nothing
        local _, len = rtf:match("^\\([a-zA-Z]+%-?%d*) ?", i)
        i = i + (len or 1) + 1
      else
        local hex = rtf:match("^\\'(%x%x)", i)
        if hex then
          text[#text + 1] = string.char(tonumber(hex, 16))
          i = i + 4
        else
          local word, digits, sp = rtf:match("^\\([a-zA-Z]+)(%-?%d*)( ?)", i)
          if word == "par" or word == "pard" or word == "line" or word == "sect" then
            text[#text + 1] = "\n"
            i = i + 1 + #word + #digits + #sp
          elseif word == "tab" then
            text[#text + 1] = " "
            i = i + 1 + #word + #digits + #sp
          elseif word == "\\" or word == "{" or word == "}" then
            text[#text + 1] = word
            i = i + 1 + #word
          elseif word then
            -- any other control word: skip it entirely
            i = i + 1 + #word + #digits + #sp
          else
            -- control symbol like \* or unknown: skip two chars
            i = i + 2
          end
        end
      end
    elseif c == "\n" or c == "\r" then
      i = i + 1 -- RTF newlines are formatting noise
    else
      if not skip_below then
        text[#text + 1] = c
      end
      i = i + 1
    end
  end

  local lines = {}
  for ln in (table.concat(text) .. "\n"):gmatch("([^\n]*)\n") do
    ln = ln:gsub("%s+$", "")
    if ln ~= "" or (lines[#lines] or "") ~= "" then
      lines[#lines + 1] = ln
    end
  end
  while lines[#lines] == "" do
    lines[#lines] = nil
  end
  while lines[1] == "" do
    table.remove(lines, 1)
  end
  return lines
end

-- --- .scrivx parsing ---------------------------------------------------------

-- Extract { title, type, children } tree from BinderItem elements. This is a
-- pragmatic regex walk over the common Scrivener 3 shape, not an XML parser.
local function parse_items(xml, from, stop_tag)
  local items = {}
  local i = from or 1
  while i <= #xml do
    local s, e, head = xml:find("<BinderItem%s+([^>]*)>", i)
    if not s then
      break
    end
    if stop_tag then
      local closer = xml:find("</" .. stop_tag .. ">", s)
      if closer and closer < e then
        break
      end
    end
    local typ = head:match("Type=\"(%w+)\"")
    local title = head:match("Title=\"(.-)\"")
    title = title
        and title:gsub("&amp;", "&"):gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&quot;", "\"")
      or nil
    -- Find matching close accounting for nested children.
    local depth = 1
    local j = e
    while depth > 0 and j <= #xml do
      local open_s, _, _ = xml:find("<BinderItem%s", j)
      local close_s = xml:find("</BinderItem>", j)
      if not close_s then
        break
      end
      if open_s and open_s < close_s then
        depth = depth + 1
        j = select(2, xml:find("<BinderItem%s[^>]*>", open_s)) + 1
      else
        depth = depth - 1
        j = close_s + #"</BinderItem>"
      end
    end
    local inner = xml:sub(e + 1, (j - #"</BinderItem>") - 1)
    local uuid = inner:match("<UUID>(.-)</UUID>")
    items[#items + 1] = {
      type = typ,
      title = title,
      uuid = uuid,
      children = parse_items(inner),
    }
    i = j
  end
  return items
end

function M.parse_scrivx(xml)
  local binder_s = xml:find("<Binder>")
  if not binder_s then
    return {}
  end
  return parse_items(xml, binder_s)
end

-- Walk the parsed binder; emit markdown per top-level Folder with Text
-- children as scenes. Returns the number of files written.
function M.import_scrivx(prj, scrivx_path)
  prj = prj or project.current()
  if not prj then
    vim.notify("[storyteller] Not in a storytelling project.", vim.log.levels.WARN)
    return nil
  end
  local ok, xml = pcall(function()
    return table.concat(vim.fn.readfile(scrivx_path), "\n")
  end)
  if not ok then
    vim.notify("[storyteller] Cannot read " .. tostring(scrivx_path), vim.log.levels.ERROR)
    return nil
  end
  local base = vim.fn.fnamemodify(scrivx_path, ":h")
  local items = M.parse_scrivx(xml)
  if #items == 0 then
    vim.notify("[storyteller] No binder items found in that .scrivx.", vim.log.levels.WARN)
    return nil
  end

  local written = 0
  local used_files = {}
  local function unique(name)
    local candidate, n = name, 1
    while used_files[candidate] do
      n = n + 1
      candidate = ("%s-%d"):format(name, n)
    end
    used_files[candidate] = true
    return candidate
  end

  local function text_file(uuid)
    if not uuid then
      return nil
    end
    local p = join(base, "Files", "Data", uuid, "content.rtf")
    if vim.loop.fs_stat(p) then
      return p
    end
    return nil
  end

  local function write_doc(prefix, name, uuid, is_chapter_like)
    local rtf_path = text_file(uuid)
    if not rtf_path then
      return 0
    end
    local okf, raw = pcall(function()
      return table.concat(vim.fn.readfile(rtf_path, false, 200000), "\n")
    end)
    if not okf then
      return 0
    end
    local body = M.rtf_to_text(raw)
    if #body == 0 then
      return 0
    end
    local fname = unique(("chapters/%s%s.md"):format(prefix, slugify(name)))
    local out = { "---", ("title: %s"):format(name:gsub("\"", "\\\"")), "---", "" }
    if not is_chapter_like then
      out[#out + 1] = "## " .. name
      out[#out + 1] = ""
    end
    for _, l in ipairs(body) do
      out[#out + 1] = l
    end
    vim.fn.mkdir(prj.root .. "/chapters", "p")
    vim.fn.writefile(out, prj.root .. "/" .. fname)
    written = written + 1
    return 1
  end

  -- Top-level folders become chapters; their Text children become scenes.
  local function walk(list, depth)
    for _, item in ipairs(list) do
      if item.type == "Folder" and item.children then
        local has_text_child = false
        for _, c in ipairs(item.children) do
          if c.type == "Text" then
            has_text_child = true
          end
        end
        if has_text_child then
          write_doc("", item.title or "Untitled folder", item.uuid, false)
          for _, c in ipairs(item.children) do
            if c.type == "Text" then
              write_doc(
                "",
                (item.title or "Chapter") .. " · " .. (c.title or "Scene"),
                c.uuid,
                false
              )
            end
          end
        else
          for _, c in ipairs(item.children) do
            if c.type == "Folder" then
              walk({ c }, depth + 1)
            elseif c.type == "Text" then
              write_doc("", c.title or "Untitled", c.uuid, false)
            end
          end
        end
      elseif item.type == "Text" then
        write_doc("", item.title or "Untitled", item.uuid, false)
      end
    end
  end

  -- Skip the standard Manuscript wrapper when present.
  local top = items
  if #top >= 1 and top[1].title == "Manuscript" and top[1].children then
    top = top[1].children
  end
  walk(top, 0)
  index.invalidate()
  return written
end

-- --- Fountain export ----------------------------------------------------------

function M.export_fountain(prj)
  prj = prj or project.current()
  if not prj then
    return nil
  end
  local ms = compile.manuscript(prj)
  local preset = compile.preset(prj)
  local out = {}
  if preset.title then
    out[#out + 1] = "Title: " .. preset.title
  end
  out[#out + 1] = ""
  for _, l in ipairs(ms) do
    local h1 = l:match("^#%s+(.*)$")
    local h2 = l:match("^##%s+(.*)$")
    if h1 then
      out[#out + 1] = "== " .. h1 .. " =="
    elseif h2 then
      -- Forced scene heading so Fountain apps treat it as a slugline.
      out[#out + 1] = "." .. h2
    else
      out[#out + 1] = l
    end
  end
  vim.fn.mkdir(prj.build, "p")
  local path = join(prj.build, "manuscript.fountain")
  vim.fn.writefile(out, path)
  return path
end

return M
