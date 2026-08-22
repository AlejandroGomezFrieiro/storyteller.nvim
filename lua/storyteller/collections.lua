-- storyteller.collections
-- Scrivener-style collections: named, saved searches over the scene index.
-- Stored at `.storyteller/collections.json`:
--   [{ "name": "Drafts", "query": "status:draft tag:war" }, ...]
--
-- Query syntax: whitespace-separated `key:value` tokens plus bare substrings.
-- Keys: status, pov, loc|location, char, tag, chapter, thread, title (bare).
-- Bare words match the scene title.

local project = require("storyteller.project")
local index = require("storyteller.index")

local M = {}

local function path(prj)
  return prj.root .. "/.storyteller/collections.json"
end

function M.list(prj)
  prj = prj or project.current()
  local out = {}
  if not prj then
    return out
  end
  local p = path(prj)
  if vim.loop.fs_stat(p) then
    local ok, lines = pcall(vim.fn.readfile, p)
    if ok then
      local ok2, data = pcall(vim.json.decode, table.concat(lines, "\n"))
      if ok2 and type(data) == "table" then
        for _, c in ipairs(data) do
          if type(c.name) == "string" and type(c.query) == "string" then
            out[#out + 1] = { name = c.name, query = c.query }
          end
        end
      end
    end
  end
  table.sort(out, function(a, b)
    return a.name < b.name
  end)
  return out
end

function M.save(prj, name, query)
  prj = prj or project.current()
  if not (prj and name and name ~= "") then
    return false
  end
  local all = M.list(prj)
  local replaced = false
  for _, c in ipairs(all) do
    if c.name == name then
      c.query = query
      replaced = true
    end
  end
  if not replaced then
    all[#all + 1] = { name = name, query = query }
  end
  vim.fn.mkdir(prj.root .. "/.storyteller", "p")
  vim.fn.writefile({ vim.json.encode(all) }, path(prj))
  return true
end

function M.delete(prj, name)
  prj = prj or project.current()
  if not prj then
    return false
  end
  local all = M.list(prj)
  local out = {}
  for _, c in ipairs(all) do
    if c.name ~= name then
      out[#out + 1] = c
    end
  end
  vim.fn.writefile({ vim.json.encode(out) }, path(prj))
  return #out < #all
end

-- Does one scene match a parsed token set?
local function matches(sc, tokens)
  local m = sc.meta or {}
  local list_has = function(list, value)
    for _, item in ipairs(type(list) == "table" and list or { list }) do
      if tostring(item):lower():find(value, 1, true) then
        return true
      end
    end
    return false
  end
  local ch_title = sc.chapter and (sc.chapter.title or "") or ""
  for _, t in ipairs(tokens) do
    local key, value = t.key, t.value
    if key == "" then
      if not (sc.title or ""):lower():find(value, 1, true) then
        return false
      end
    elseif key == "status" then
      if not (m.status or "outline"):lower():find(value, 1, true) then
        return false
      end
    elseif key == "pov" then
      if not list_has(m.pov, value) then
        return false
      end
    elseif key == "loc" or key == "location" then
      if not list_has(m.location, value) then
        return false
      end
    elseif key == "char" then
      if not list_has(m.chars, value) then
        return false
      end
    elseif key == "tag" then
      if not list_has(m.tags, value) then
        return false
      end
    elseif key == "thread" then
      if not (list_has(m.setup, value) or list_has(m.payoff, value)) then
        return false
      end
    elseif key == "plotline" then
      if not list_has(m.plotlines, value) then
        return false
      end
    elseif key == "stage" then
      if not (m.stage and tostring(m.stage):lower():find(value, 1, true)) then
        return false
      end
    elseif key == "timeline" then
      local on_axis = m.timeline and tostring(m.timeline):lower():find(value, 1, true)
      for _, entry in ipairs(type(m.also) == "table" and m.also or { m.also }) do
        local ax = entry and tostring(entry):match("timeline:%s*([^,}]+)")
        if ax and ax:lower():find(value, 1, true) then
          on_axis = true
        end
      end
      if not on_axis then
        return false
      end
    elseif key == "chapter" then
      if not ch_title:lower():find(value, 1, true) then
        return false
      end
    end
  end
  return true
end

-- Parse a query into tokens.
function M.parse(query)
  local tokens = {}
  for tok in (query or ""):gmatch("%S+") do
    local key, value = tok:match("^([%w_]+):(.*)$")
    if key then
      tokens[#tokens + 1] = { key = key:lower(), value = value:lower() }
    else
      tokens[#tokens + 1] = { key = "", value = tok:lower() }
    end
  end
  return tokens
end

-- Run a query; returns matching scenes in manuscript order.
function M.run(prj, query)
  local tokens = M.parse(query)
  local out = {}
  for _, sc in ipairs(index.scenes(prj)) do
    if matches(sc, tokens) then
      out[#out + 1] = sc
    end
  end
  return out
end

return M
