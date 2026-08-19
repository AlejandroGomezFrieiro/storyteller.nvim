-- storyteller.schema
-- Single source of truth for Storyteller's metadata vocabulary.
--
-- Everything that reads or writes a story field (the plugin, the nixvim_config
-- snippets, the exporter) should reference the names and orders defined here so
-- the schema has exactly one home.

local M = {}

-- Workflow statuses, in the order scenes advance through them.
M.statuses = { "outline", "draft", "revision", "done", "unused" }
M.status_next = {
  outline = "draft",
  draft = "revision",
  revision = "done",
  done = "unused",
  unused = "outline",
}

-- Fields that belong to a scene (its own workflow state), in canonical order.
M.scene_fields = {
  "id", "status", "planning", "pov", "location", "time",
  "goal", "conflict", "outcome", "beat", "target", "tags",
  "chars", "locs", "items", "orgs", "ignore",
}

-- Fields that belong to a chapter (shared defaults, targets, links), canonical
-- order. `pov`/`location`/`status` may also live here as chapter-wide defaults.
M.chapter_fields = {
  "type", "pov", "location", "status", "planning", "target",
  "chars", "locs", "items", "orgs", "ignore", "tags", "aliases", "names",
}

-- List-typed fields, serialized as `key:` + indented `- item`.
M.list_fields = {
  tags = true,
  chars = true,
  locs = true,
  items = true,
  orgs = true,
  ignore = true,
  aliases = true,
  names = true,
}

-- Reference types declared in the shared schema. Keyed by singular id; each
-- entry maps a folder (dir) to a scene-list field and a card body template.
-- Custom codex types (folders not listed here) are still first-class: the
-- folder name becomes the type id and the list field.
M.reference_types = {
  character = { dir = "characters", label = "Character", field = "chars", body = { "Role", "Notes" } },
  location = { dir = "locations", label = "Location", field = "locs", body = { "Atmosphere", "Notes" } },
  item = { dir = "items", label = "Item", field = "items", body = { "Type", "Notes" } },
  organization = { dir = "organizations", label = "Organization", field = "orgs", body = { "Wants", "Members", "Notes" } },
}

-- Folder (plural, e.g. "characters") -> scene-list field. Unknown folders map
-- to themselves (a `creatures:` folder links into a `creatures` list).
M.type_field = function(dir)
  for _, t in pairs(M.reference_types) do
    if t.dir == dir then
      return t.field
    end
  end
  return dir
end

-- Folder -> human label; unknown folders get a prettified folder name.
M.type_label = function(dir)
  for _, t in pairs(M.reference_types) do
    if t.dir == dir then
      return t.label
    end
  end
  return dir:gsub("^%l", string.upper):gsub("[_-]", " ")
end

-- Folder -> card body bullets (used when creating a new card).
M.type_body = function(dir)
  for _, t in pairs(M.reference_types) do
    if t.dir == dir then
      return t.body
    end
  end
  return { "Notes" }
end

-- All known type folders: schema-declared first, then any discovered on disk.
M.type_dirs = function(prj_dirs)
  local out = {}
  local seen = {}
  for _, t in pairs(M.reference_types) do
    if not seen[t.dir] then
      seen[t.dir] = true
      out[#out + 1] = t.dir
    end
  end
  for _, d in ipairs(prj_dirs or {}) do
    if not seen[d] then
      seen[d] = true
      out[#out + 1] = d
    end
  end
  return out
end

-- The `storyteller: scene` sentinel that marks a scene-local YAML block.
M.scene_sentinel = "storyteller: scene"

M.is_list = function(key)
  return M.list_fields[key] == true
end

M.is_scene_field = function(key)
  return vim.tbl_contains(M.scene_fields, key)
end

M.is_chapter_field = function(key)
  return vim.tbl_contains(M.chapter_fields, key)
end

M.valid_status = function(s)
  return vim.tbl_contains(M.statuses, s or "")
end

M.next_status = function(s)
  return M.status_next[s] or M.statuses[1]
end

return M
