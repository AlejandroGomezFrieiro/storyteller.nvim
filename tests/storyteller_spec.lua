-- Run with: nvim --headless -u NONE -l tests/storyteller_spec.lua
local root = vim.fn.fnamemodify(vim.fn.getcwd(), ":p")
vim.opt.runtimepath:prepend(root)

local passed, failed = 0, 0
local function assert_true(condition, label)
  if condition then
    passed = passed + 1
    print("PASS " .. label)
  else
    failed = failed + 1
    print("FAIL " .. label)
  end
end

local function words(count)
  local out = {}
  for i = 1, count do
    out[i] = "word"
  end
  return table.concat(out, " ")
end

local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp .. "/chapters", "p")
vim.fn.writefile({}, tmp .. "/.storyteller")

local project = require("storyteller.project")
local config = require("storyteller.config")
local meta = require("storyteller.meta")
local track = require("storyteller.track")
local compile = require("storyteller.compile")
local index = require("storyteller.index")
require("storyteller.ui")
require("storyteller.ui.views")
require("storyteller.ui.dashboard")

-- An explicit marker must be enough to bootstrap the standard layout.
local marker_project = project.resolve(tmp .. "/idea.md")
assert_true(marker_project ~= nil and marker_project.chapters == tmp .. "/chapters", "marker-only project resolves")

-- A later explicit setup must override automatic/default settings.
config.setup({ picker = "auto" })
config.setup({ picker = "fzf" })
assert_true(config.get().picker == "fzf", "later config setup overrides defaults")

local chapter = tmp .. "/chapters/01.md"
local prj = project.paths_for(tmp, true)
vim.fn.writefile({
  "---",
  "# editorial comment",
  "status: draft",
  "custom:",
  "  nested: keep-me",
  "---",
  "# Chapter 1 — Test",
  "",
  "## Scene 1",
  words(10),
}, chapter)

meta.chapter_write(chapter, { status = "done" })
local after_metadata = table.concat(vim.fn.readfile(chapter), "\n")
assert_true(after_metadata:find("# editorial comment", 1, true) ~= nil, "metadata mutation preserves comments")
assert_true(after_metadata:find("nested: keep%-me") ~= nil, "metadata mutation preserves unsupported YAML")
assert_true(after_metadata:find("status: done", 1, true) ~= nil, "metadata mutation updates managed field")

vim.fn.writefile({
  "# Chapter 1", "## Scene 1", "```yaml", "storyteller: scene",
  "status: revision", "pov: Odysseus", "tags:", "  - act-1", "```",
  "ten words belong to prose and not metadata here today",
}, chapter)
local parsed_scene = index.scenes(prj)[1]
assert_true(parsed_scene.meta.status == "revision" and parsed_scene.meta.pov == "Odysseus", "scene YAML metadata is indexed")
assert_true(index.scene_words(parsed_scene) == 10, "scene word count excludes YAML block")
assert_true(meta.ensure_id(parsed_scene) ~= nil, "scene receives stable ID when needed")

local balance = track.pov_balance(prj)
assert_true(balance.povs["Odysseus"] == 1, "pov_balance counts POV scenes")
assert_true(balance.tags["act-1"] == 1, "pov_balance counts tag usage")

-- The progress format stores a cumulative total so day three is a real delta.
local original_date = os.date
local dates = { "2026-01-01", "2026-01-02", "2026-01-03" }
local day = 1
os.date = function(format)
  if format == "%Y-%m-%d" then
    return dates[day]
  end
  return original_date(format)
end
vim.fn.writefile({ "# Chapter 1", words(10) }, chapter)
track.progress_append(prj)
vim.fn.writefile({ "# Chapter 1", words(20) }, chapter)
day = 2
track.progress_append(prj)
vim.fn.writefile({ "# Chapter 1", words(25) }, chapter)
day = 3
track.progress_append(prj)
os.date = original_date
local progress = vim.fn.readfile(tmp .. "/progress.log")
assert_true(progress[1] == "2026-01-01 10 10", "progress records first total")
assert_true(progress[2] == "2026-01-02 10 20", "progress records second-day delta")
assert_true(progress[3] == "2026-01-03 5 25", "progress records third-day delta")

-- Scrivenings must synchronize a clean source buffer after write-back.
vim.cmd("edit " .. vim.fn.fnameescape(chapter))
local source_buf = vim.api.nvim_get_current_buf()
local scriv_buf = compile.open(prj)
local lines = vim.api.nvim_buf_get_lines(scriv_buf, 0, -1, false)
for i, line in ipairs(lines) do
  if line:find("word word", 1, true) then
    lines[i] = "synchronized prose"
    break
  end
end
vim.api.nvim_buf_set_lines(scriv_buf, 0, -1, false, lines)
vim.cmd("write")
local source_lines = table.concat(vim.api.nvim_buf_get_lines(source_buf, 0, -1, false), "\n")
assert_true(source_lines:find("synchronized prose", 1, true) ~= nil, "Scrivenings updates clean source buffer")

-- A modified source buffer must not be allowed to overwrite Scrivenings output.
vim.api.nvim_buf_set_lines(source_buf, 0, 1, false, { "unsaved conflicting buffer" })
local conflict_scriv = compile.open(prj, { bang = true })
local conflict_lines = vim.api.nvim_buf_get_lines(conflict_scriv, 0, -1, false)
for i, line in ipairs(conflict_lines) do
  if line:find("synchronized prose", 1, true) then
    conflict_lines[i] = "new Scrivenings prose"
    break
  end
end
vim.api.nvim_buf_set_lines(conflict_scriv, 0, -1, false, conflict_lines)
vim.cmd("write")
assert_true(vim.bo[source_buf].readonly, "Scrivenings protects modified stale source buffer")

-- A fake pandoc copies its input so export output can be inspected without a
-- document toolchain. Storyteller metadata must not leak into it.
local fake_bin = tmp .. "/bin"
vim.fn.mkdir(fake_bin, "p")
local fake_pandoc = fake_bin .. "/pandoc"
vim.fn.writefile({
  "#!/bin/sh",
  "for arg in \"$@\"; do case \"$arg\" in --output=*) output=${arg#--output=};; esac; done",
  "cp \"$1\" \"$output\"",
}, fake_pandoc)
vim.fn.setfperm(fake_pandoc, "rwxr-xr-x")
local old_path = vim.env.PATH
vim.env.PATH = fake_bin .. ":" .. old_path
vim.fn.writefile({
  "---", "status: draft", "chars:", "  - Odysseus", "---",
  "# Chapter 1", "visible manuscript prose",
  "", "## Scene 1",
  "- [ ] plan the reunion",
  "- **POV:** Odysseus",
  "- **Location:** Ithaca",
  "```yaml", "storyteller: scene", "status: outline", "pov: Odysseus", "```",
}, chapter)
local output = compile.export(prj, "docx")
local compiled = output and table.concat(vim.fn.readfile(output), "\n") or ""
assert_true(compiled:find("visible manuscript prose", 1, true) ~= nil, "export includes chapter prose")
assert_true(compiled:find("status: draft", 1, true) == nil, "export excludes chapter frontmatter")
assert_true(compiled:find("plan the reunion", 1, true) == nil, "export excludes planning checklists")
assert_true(compiled:find("POV:", 1, true) == nil, "export excludes inline metadata fields")
assert_true(compiled:find("storyteller: scene", 1, true) == nil, "export excludes scene YAML blocks")
local chapter_outputs = compile.export_all(prj, "epub")
vim.env.PATH = old_path
assert_true(chapter_outputs and #chapter_outputs == 1, "export all creates one output per chapter")

-- The migration rewrites inline bullets into scene YAML.
vim.fn.writefile({
  "# Chapter 1",
  "## Scene 1",
  "- **POV:** Odysseus",
  "- **Location:** Ithaca",
  "some prose words here",
}, chapter)
local migrated = meta.migrate(chapter)
assert_true(migrated == 1, "inline metadata migrates to a scene YAML block")
local migrated_lines = table.concat(vim.fn.readfile(chapter), "\n")
assert_true(migrated_lines:find("storyteller: scene", 1, true) ~= nil, "migration emits scene YAML sentinel")
assert_true(migrated_lines:find("%- %*%*POV:%*%*") == nil, "migration removes inline POV bullet")

require("storyteller").setup({ autocmds = false })
assert_true(vim.fn.exists(":Story") == 2, ":Story command is registered")

-- Command surface: the new subcommands are registered.
local commands = require("storyteller.commands")
for _, name in ipairs({ "capture", "idea", "ideas", "snapshots", "template", "export", "workspace", "palette" }) do
  assert_true(commands.handlers[name] ~= nil, "command '" .. name .. "' is registered")
end
local comp = commands.complete("out")
assert_true(comp[1] == "outline", "command completion suggests 'outline'")

-- Capture: create a reference card from a name.
local capture = require("storyteller.capture")
local card = capture.create(prj, "character", "Cassandra")
assert_true(card ~= nil and vim.fn.filereadable(card) == 1, "capture creates a character card")
local card_text = table.concat(vim.fn.readfile(card), "\n")
assert_true(card_text:find("names:", 1, true) ~= nil, "capture card has names frontmatter")
assert_true(card_text:find("## Cassandra", 1, true) ~= nil, "capture card has heading")

-- Ideas inbox.
local ideas = require("storyteller.ideas")
ideas.append(prj, "the storm was arranged")
local ideas_text = table.concat(vim.fn.readfile(tmp .. "/research/ideas.md"), "\n")
assert_true(ideas_text:find("the storm was arranged", 1, true) ~= nil, "ideas append to research/ideas.md")

-- Template plan reports created/skipped without writing.
local templates = require("storyteller.templates")
local plan = templates.plan(prj, "three-act-structure")
assert_true(plan ~= nil and #plan.created > 0, "template plan lists chapters to create")

-- Scene metadata resolution: scene YAML wins, chapter frontmatter is a default.
local ch2 = tmp .. "/chapters/02_resolution.md"
vim.fn.writefile({
  "---", "status: draft", "target: 2000", "---",
  "# Chapter 2 — Resolution",
  "## Scene 1",
  "```yaml", "storyteller: scene", "status: revision", "pov: Odysseus", "```",
  "prose words here",
}, ch2)
local scene2
for _, sc in ipairs(index.scenes(prj)) do
  if sc.path == ch2 then
    scene2 = sc
  end
end
assert_true(scene2 ~= nil, "resolution chapter is indexed")
assert_true(scene2.meta.status == "revision", "scene status overrides chapter status")
assert_true(scene2.meta.target == 2000, "chapter target is a default for the scene")
local resolved = meta.scene(scene2).meta
assert_true(resolved.status == "revision" and resolved.target == 2000, "meta.scene resolves scene -> chapter")

-- Tracking stats: heatmap, streaks, milestones shapes.
local heat = track.heatmap(prj, 4)
assert_true(#heat == 28, "heatmap covers 4 weeks")
local streaks = track.streaks(prj)
assert_true(type(streaks.current) == "number" and type(streaks.longest) == "number", "streaks returns numbers")
assert_true(#track.milestones(prj) > 0, "milestones returns entries")

-- Snapshots are git-only and never create documents.
local snapshot = require("storyteller.snapshot")
local snap = snapshot.snapshot(prj)
assert_true(vim.fn.isdirectory(tmp .. "/build/snapshots") == 0, "snapshot never creates build/snapshots")
if snap and snap.type == "git" then
  local log = vim.fn.systemlist({ "git", "-C", tmp, "log", "--oneline" })
  assert_true(#log > 0, "git snapshot creates a commit")
end

-- Schema consistency: schema.lua must mirror server/schema.json.
local schema = require("storyteller.schema")
local schema_json = vim.json.decode(table.concat(vim.fn.readfile(root .. "/server/schema.json"), "\n"))
assert_true(vim.deep_equal(schema.statuses, schema_json.statuses), "schema.statuses matches schema.json")
assert_true(vim.deep_equal(schema.scene_fields, schema_json.scene_fields), "schema.scene_fields matches schema.json")
assert_true(vim.deep_equal(schema.chapter_fields, schema_json.chapter_fields), "schema.chapter_fields matches schema.json")
local list_fields = {}
for k in pairs(schema.list_fields) do
  list_fields[#list_fields + 1] = k
end
table.sort(list_fields)
local json_list = {}
for _, k in ipairs(schema_json.list_fields) do
  json_list[#json_list + 1] = k
end
table.sort(json_list)
assert_true(vim.deep_equal(list_fields, json_list), "schema.list_fields matches schema.json")

for id, t in pairs(schema_json.reference_types) do
  local lua_t = schema.reference_types[id]
  assert_true(lua_t ~= nil, "schema.reference_types." .. id .. " matches schema.json")
  assert_true(lua_t.dir == t.dir and lua_t.label == t.label and lua_t.field == t.field, "schema.reference_types." .. id .. " fields match schema.json")
  assert_true(vim.deep_equal(lua_t.body, t.body), "schema.reference_types." .. id .. " body matches schema.json")
  assert_true(vim.deep_equal(lua_t.min_fields, t.min_fields), "schema.reference_types." .. id .. " min_fields matches schema.json")
end
assert_true(vim.deep_equal(schema.status_next, schema_json.status_next), "schema.status_next matches schema.json")
assert_true(vim.deep_equal(schema.scene_field_defs, schema_json.scene_field_defs), "schema.scene_field_defs matches schema.json")
assert_true(vim.deep_equal(schema.chapter_field_defs, schema_json.chapter_field_defs), "schema.chapter_field_defs matches schema.json")
assert_true(vim.deep_equal(schema.enums, schema_json.enums), "schema.enums matches schema.json")
assert_true(vim.deep_equal(schema.diagnostics, schema_json.diagnostics), "schema.diagnostics matches schema.json")

-- A folder outside the built-in types is still a first-class reference type.
local codex_project = vim.fn.tempname()
vim.fn.mkdir(codex_project .. "/references/creatures", "p")
vim.fn.mkdir(codex_project .. "/chapters", "p")
vim.fn.writefile({
  "---", "names:",
  "  - Gr'hall", "---", "", "## Gr'hall", "", "- **Notes:** ",
}, codex_project .. "/references/creatures/grhall.md")
vim.fn.writefile({ "# Chapter 1", "## S1", "Gr'hall lurks here." }, codex_project .. "/chapters/01.md")
local codex_prj = project.paths_for(codex_project, true)
local refs = index.references(codex_prj)
assert_true(refs["creatures"] ~= nil and #refs["creatures"] == 1, "arbitrary references/creatures folder is indexed")
assert_true(schema.type_field("creatures") == "creatures", "custom type links into a folder-named field")
assert_true(schema.type_label("creatures") == "Creatures", "custom type gets a derived label")
local detect = require("storyteller.detect")
local sugs = detect.detect_scene(index.scenes(codex_prj)[1], codex_prj)
assert_true(#sugs == 1 and sugs[1].type == "creatures", "detection yields suggestions for custom types")
detect.link(index.scenes(codex_prj)[1], sugs[1].reference)
local sc = index.scenes(codex_prj)[1]
local after = table.concat(vim.fn.readfile(sc.path), "\n")
assert_true(after:find("creatures:\n  %- Gr'hall") ~= nil, "custom type links into its folder-named field")
vim.fn.delete(codex_project, "rf")

-- Runtime schema merge: project layers override, delete, and add to defaults.
local schema_proj = vim.fn.tempname()
vim.fn.mkdir(schema_proj .. "/.storyteller", "p")
vim.fn.writefile({
  '{',
  '  "reference_types": { "item": null },',
  '  "enums": { "moods": ["tense", "calm"] },',
  '  "diagnostics": { "unknown_field": false }',
  '}',
}, schema_proj .. "/.storyteller/schema.json")
local loaded = schema.load(schema_proj)
assert_true(loaded.reference_types.item == nil, "project schema deletes the item type")
assert_true(vim.deep_equal(loaded.enums, { moods = { "tense", "calm" } }), "project schema adds an enum")
assert_true(schema.flag("unknown_field") == false, "diagnostics toggle is overridable")
assert_true(schema.flag("missing_id") == false, "default diagnostics toggles survive merge")

-- Write the merged schema, drop the project layer, and reload from the write.
local written = schema.write(schema_proj)
assert_true(vim.loop.fs_stat(written) ~= nil, "schema write creates storyteller.schema.json")
vim.fn.delete(schema_proj .. "/.storyteller/schema.json")
schema.invalidate(schema_proj)
local reloaded = schema.dump(schema_proj)
assert_true(reloaded.reference_types.item == nil, "schema write round-trip preserves overrides")
vim.fn.delete(schema_proj, "rf")

-- .storyteller.toml can point at a schema under a custom path.
local toml_proj = vim.fn.tempname()
vim.fn.mkdir(toml_proj .. "/config", "p")
vim.fn.writefile({ '{ "reference_types": { "faction": { "dir": "factions", "label": "Faction", "field": "factions" } } }' }, toml_proj .. "/config/schema.json")
vim.fn.writefile({ "[storyteller]", 'schema = "config/schema.json"' }, toml_proj .. "/.storyteller.toml")
local toml_loaded = schema.load(toml_proj)
assert_true(toml_loaded.reference_types.faction ~= nil, ".storyteller.toml points at a schema")
assert_true(schema.type_field("factions") == "factions", "custom faction type resolves its field")
assert_true(schema.type_label("factions") == "Faction", "custom faction type gets its label")
vim.fn.delete(toml_proj, "rf")

vim.fn.delete(tmp, "rf")
print(("RESULT: %d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
