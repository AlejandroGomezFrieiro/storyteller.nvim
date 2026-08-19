-- storyteller.meta
-- Unified metadata API: a single facade over read + write.
--
--   meta.chapter(path)            read chapter frontmatter document
--   meta.scene(scene)             resolve a scene's merged metadata
--   meta.field(scene, key, dflt)  resolve one field
--   meta.chapter_write(path, patch)
--   meta.scene_write(scene, patch)
--   meta.scene_set(scene, meta)
--   meta.set_field(scene, key, value)
--   meta.ensure_id(scene)
--   meta.migrate(path)            inline bullets -> scene YAML

local read = require("storyteller.meta.read")
local write = require("storyteller.meta.write")
local serde = require("storyteller.meta.serde")
local schema = require("storyteller.schema")

local M = {}

for k, v in pairs(read) do
  M[k] = v
end
for k, v in pairs(write) do
  M[k] = v
end

M.serde = serde
M.schema = schema

return M
