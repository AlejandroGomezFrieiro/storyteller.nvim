-- storyteller.projections
-- Editable text projections of project state (docs/projections.md).
--
--   render(name, prj)                 -> { lines, text, records }
--   diff(name, prj, old_lines, new)   -> ops[] | nil, err
--   apply(name, prj, ops)             -> applied count | nil, err
--   commit(name, prj, old_lines, new) -> applied count | nil, err
--
-- Ops are a small closed set: one optional `reorder` (the complete new global
-- scene sequence) plus `set_field` / `set_chapter_field` writes. Apply is
-- transactional in intent: the reorder is validated across every touched file
-- before any disk write; field writes re-resolve scenes from the fresh index
-- afterwards.

local project = require("storyteller.project")
local index = require("storyteller.index")
local meta = require("storyteller.meta")
local reorder = require("storyteller.reorder")

local M = {}

local mods = {
  corkboard = require("storyteller.projections.corkboard"),
  timeline = require("storyteller.projections.timeline"),
  synopsis = require("storyteller.projections.synopsis"),
  metasheet = require("storyteller.projections.metasheet"),
}

function M.names()
  local out = {}
  for name in pairs(mods) do
    out[#out + 1] = name
  end
  table.sort(out)
  return out
end

function M.render(name, prj, opts)
  local mod = mods[name]
  if not mod then
    return nil, "unknown projection: " .. tostring(name)
  end
  local ok, out
  if name == "timeline" and opts and opts ~= "" then
    ok, out = pcall(mod.render, prj, tostring(opts))
  else
    ok, out = pcall(mod.render, prj)
  end
  if not ok then
    return nil, tostring(out)
  end
  out.name = name
  out.text = table.concat(out.lines, "\n")
  return out
end

function M.diff(name, prj, old_lines, new_lines)
  local mod = mods[name]
  if not mod then
    return nil, "unknown projection: " .. tostring(name)
  end
  local ok, ops = pcall(mod.diff, mod.parse(old_lines), mod.parse(new_lines), prj)
  if not ok then
    return nil, tostring(ops)
  end
  return ops
end

-- --- Op application ----------------------------------------------------------

local function op_path(prj, o)
  return o.path or (o.rel and (prj.root .. "/" .. o.rel)) or nil
end

local function is_git(root)
  vim.fn.system({ "git", "-C", root, "rev-parse", "--git-dir" })
  return vim.v.shell_error == 0
end

-- Rebuild chapters so each file holds exactly its projected scene sequence.
-- `files` maps relative chapter paths to ordered raw-title lists and must
-- account for every scene in the project; files vacated by moves are emptied
-- of the moved blocks automatically.
function M.apply_reorder(prj, files)
  -- Gather every existing chapter (rel path) plus every projected one.
  local rels = {}
  local seen = {}
  for _, ch in ipairs(index.chapters(prj)) do
    local rel = require("storyteller.projections.corkboard").rel(prj, ch.path)
    rels[#rels + 1] = rel
    seen[rel] = true
  end
  for rel in pairs(files) do
    if not seen[rel] then
      rels[#rels + 1] = rel
      seen[rel] = true
    end
  end

  -- Validate everything first: no modified buffers, no missing/duplicate or
  -- unknown scenes. A scene may move between files freely; identity is its
  -- heading text. Nothing is written until all plans check out.
  local claimed = {}
  for rel, titles in pairs(files) do
    for _, t in ipairs(titles) do
      if claimed[t] then
        return nil, ("scene %q appears twice in the projected order"):format(t)
      end
      claimed[t] = true
    end
  end

  local plans = {}
  local pool = {} -- title -> { blk = lines, rel = source file }
  for _, rel in ipairs(rels) do
    local path = prj.root .. "/" .. rel
    for _, b in ipairs(vim.fn.getbufinfo({ bufloaded = 1 })) do
      if vim.api.nvim_buf_get_name(b.bufnr) == path and b.changed ~= 0 then
        return nil, "unsaved edits in " .. rel .. "; apply refused"
      end
    end
    local lines = vim.fn.readfile(path)
    if not lines then
      if not files[rel] then
        goto continue
      end
      return nil, "cannot read " .. rel
    end
    local parts = reorder.split_scenes(lines, nil)
    local heads = {}
    for _, blk in ipairs(parts.blocks) do
      local head = vim.trim(blk[1]:match("^##%s+(.*)$") or blk[1])
      heads[#heads + 1] = head
      if pool[head] then
        return nil, ("duplicate scene heading %q across chapters"):format(head)
      end
      pool[head] = { blk = blk, rel = rel }
      if not claimed[head] then
        return nil, ("scene %q is missing from the projected order"):format(head)
      end
      claimed[head] = nil
    end
    local desired = files[rel] or {}
    local same = #heads == #desired
    if same then
      for i, t in ipairs(desired) do
        if heads[i] ~= t then
          same = false
          break
        end
      end
    end
    plans[#plans + 1] = { path = path, rel = rel, parts = parts, desired = desired, same = same }
    ::continue::
  end
  local unclaimed = next(claimed)
  if unclaimed then
    return nil, ("scene %q is not in any chapter file"):format(unclaimed)
  end

  -- Safety net: snapshot before structural rewrites (git projects only, so
  -- headless/test contexts without git stay silent).
  if is_git(prj.root) then
    pcall(function()
      vim.fn.system({
        "git",
        "-C",
        prj.root,
        "commit",
        "-m",
        "storyteller:snapshot " .. os.date("%Y%m%d-%H%M%S") .. " — before storyboard apply",
      })
    end)
  end

  local changed = 0
  for _, plan in ipairs(plans) do
    if not plan.same then
      local out = {}
      for _, l in ipairs(plan.parts.pre) do
        out[#out + 1] = l
      end
      for i, title in ipairs(plan.desired) do
        local entry = pool[title]
        if not entry then
          return nil, ("scene %q not found for rebuild"):format(title)
        end
        for _, l in ipairs(entry.blk) do
          out[#out + 1] = l
        end
        if i < #plan.desired then
          out[#out + 1] = ""
        end
      end
      reorder.write_file(plan.path, out)
      changed = changed + 1
    end
  end
  return changed
end

function M.apply(_name, prj, ops)
  prj = prj or project.current()
  if not prj then
    return nil, "no project"
  end
  local applied = 0

  -- Structural pass first.
  for _, o in ipairs(ops) do
    if o.op == "reorder" then
      local n, err = M.apply_reorder(prj, o.files)
      if not n then
        return nil, err
      end
      applied = applied + n
    end
  end

  -- Field pass: resolve scenes against the fresh index.
  index.invalidate()
  local function find_scene(o)
    local path = op_path(prj, o)
    for _, sc in ipairs(index.scenes(prj)) do
      if sc.path == path and sc.title == o.raw_title then
        return sc
      end
    end
    return nil
  end

  for _, o in ipairs(ops) do
    -- nil means "remove the field"; the write layer understands vim.NIL.
    local value = o.value == nil and vim.NIL or o.value
    if o.op == "set_field" then
      local sc
      if o.path or o.rel then
        sc = find_scene(o)
        if not sc then
          return nil, ("scene %q not found for field write"):format(o.raw_title or "?")
        end
      else
        -- Identity by raw title alone (timeline/metasheet edits).
        for _, sc2 in ipairs(index.scenes(prj)) do
          if sc2.title == o.raw_title then
            sc = sc2
            break
          end
        end
        if not sc then
          return nil, ("scene %q not found for field write"):format(o.raw_title or "?")
        end
      end
      local ok, err = pcall(meta.set_field, sc, o.key, value)
      if not ok then
        return nil, tostring(err)
      end
      applied = applied + 1
    elseif o.op == "set_chapter_field" then
      local path = op_path(prj, o)
      if not path then
        return nil, ("cannot resolve the file for %q"):format(o.raw_title or o.key)
      end
      local ok, err = pcall(meta.chapter_write, path, { [o.key] = value })
      if not ok then
        return nil, tostring(err)
      end
      applied = applied + 1
    end
  end
  index.invalidate()
  return applied
end

function M.commit(name, prj, old_lines, new_lines)
  local ops, err = M.diff(name, prj, old_lines, new_lines)
  if not ops then
    return nil, err
  end
  if #ops == 0 then
    return 0
  end
  return M.apply(name, prj, ops)
end

return M
