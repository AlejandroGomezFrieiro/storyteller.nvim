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
