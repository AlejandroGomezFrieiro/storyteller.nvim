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
local ui = require("storyteller.ui")
local views = require("storyteller.ui.views")
require("storyteller.ui.dashboard")

-- An explicit marker must be enough to bootstrap the standard layout.
local marker_project = project.resolve(tmp .. "/idea.md")
assert_true(
  marker_project ~= nil and marker_project.chapters == tmp .. "/chapters",
  "marker-only project resolves"
)

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
assert_true(
  after_metadata:find("# editorial comment", 1, true) ~= nil,
  "metadata mutation preserves comments"
)
assert_true(
  after_metadata:find("nested: keep%-me") ~= nil,
  "metadata mutation preserves unsupported YAML"
)
assert_true(
  after_metadata:find("status: done", 1, true) ~= nil,
  "metadata mutation updates managed field"
)

vim.fn.writefile({
  "# Chapter 1",
  "## Scene 1",
  "```yaml",
  "storyteller: scene",
  "status: revision",
  "pov: Odysseus",
  "tags:",
  "  - act-1",
  "```",
  "ten words belong to prose and not metadata here today",
}, chapter)
local parsed_scene = index.scenes(prj)[1]
assert_true(
  parsed_scene.meta.status == "revision" and parsed_scene.meta.pov == "Odysseus",
  "scene YAML metadata is indexed"
)
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
assert_true(
  source_lines:find("synchronized prose", 1, true) ~= nil,
  "Scrivenings updates clean source buffer"
)

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
  "---",
  "status: draft",
  "chars:",
  "  - Odysseus",
  "---",
  "# Chapter 1",
  "visible manuscript prose",
  "",
  "## Scene 1",
  "- [ ] plan the reunion",
  "- **POV:** Odysseus",
  "- **Location:** Ithaca",
  "```yaml",
  "storyteller: scene",
  "status: outline",
  "pov: Odysseus",
  "```",
}, chapter)
local output = compile.export(prj, "docx")
local compiled = output and table.concat(vim.fn.readfile(output), "\n") or ""
assert_true(
  compiled:find("visible manuscript prose", 1, true) ~= nil,
  "export includes chapter prose"
)
assert_true(compiled:find("status: draft", 1, true) == nil, "export excludes chapter frontmatter")
assert_true(
  compiled:find("plan the reunion", 1, true) == nil,
  "export excludes planning checklists"
)
assert_true(compiled:find("POV:", 1, true) == nil, "export excludes inline metadata fields")
assert_true(
  compiled:find("storyteller: scene", 1, true) == nil,
  "export excludes scene YAML blocks"
)
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
assert_true(
  migrated_lines:find("storyteller: scene", 1, true) ~= nil,
  "migration emits scene YAML sentinel"
)
assert_true(migrated_lines:find("%- %*%*POV:%*%*") == nil, "migration removes inline POV bullet")

require("storyteller").setup({ autocmds = false })
assert_true(vim.fn.exists(":Story") == 2, ":Story command is registered")

-- The corkboard is a storyboard now: an editable projection buffer.
local _, cork_bounds = ui.compose_columns({
  { { text = "╭─" } },
  { { text = "╭─" } },
}, 1)
assert_true(cork_bounds[2].start == 4, "Unicode panel bounds use display width")
local cork_ok = pcall(require("storyteller.ui.storyboard").open, "corkboard", prj)
local cork_text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
assert_true(
  cork_ok and cork_text:find("# Corkboard", 1, true) ~= nil and vim.bo[0].buftype == "acwrite",
  "corkboard renders scene cards"
)

-- Command surface: the new subcommands are registered.
local commands = require("storyteller.commands")
for _, name in ipairs({
  "capture",
  "idea",
  "ideas",
  "snapshots",
  "template",
  "export",
  "workspace",
  "palette",
}) do
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
assert_true(
  ideas_text:find("the storm was arranged", 1, true) ~= nil,
  "ideas append to research/ideas.md"
)

-- Template plan reports created/skipped without writing.
local templates = require("storyteller.templates")
local plan = templates.plan(prj, "three-act-structure")
assert_true(plan ~= nil and #plan.created > 0, "template plan lists chapters to create")

-- Scene metadata resolution: scene YAML wins, chapter frontmatter is a default.
local ch2 = tmp .. "/chapters/02_resolution.md"
vim.fn.writefile({
  "---",
  "status: draft",
  "target: 2000",
  "---",
  "# Chapter 2 — Resolution",
  "## Scene 1",
  "```yaml",
  "storyteller: scene",
  "status: revision",
  "pov: Odysseus",
  "```",
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
assert_true(
  resolved.status == "revision" and resolved.target == 2000,
  "meta.scene resolves scene -> chapter"
)

-- Tracking stats: heatmap, streaks, milestones shapes.
local heat = track.heatmap(prj, 4)
assert_true(#heat == 28, "heatmap covers 4 weeks")
local streaks = track.streaks(prj)
assert_true(
  type(streaks.current) == "number" and type(streaks.longest) == "number",
  "streaks returns numbers"
)
assert_true(#track.milestones(prj) > 0, "milestones returns entries")

-- Snapshots are git-only and never create documents.
local snapshot = require("storyteller.snapshot")
local snap = snapshot.snapshot(prj)
assert_true(
  vim.fn.isdirectory(tmp .. "/build/snapshots") == 0,
  "snapshot never creates build/snapshots"
)
if snap and snap.type == "git" then
  local log = vim.fn.systemlist({ "git", "-C", tmp, "log", "--oneline" })
  assert_true(#log > 0, "git snapshot creates a commit")
end

-- Schema consistency: schema.lua must mirror the bundled canonical schema.json.
local schema = require("storyteller.schema")
local schema_json =
  vim.json.decode(table.concat(vim.fn.readfile(root .. "/lua/storyteller/schema.json"), "\n"))
assert_true(schema.version == schema_json.version, "schema.version matches schema.json")
assert_true(
  vim.deep_equal(schema.statuses, schema_json.statuses),
  "schema.statuses matches schema.json"
)
assert_true(
  vim.deep_equal(schema.scene_fields, schema_json.scene_fields),
  "schema.scene_fields matches schema.json"
)
assert_true(
  vim.deep_equal(schema.chapter_fields, schema_json.chapter_fields),
  "schema.chapter_fields matches schema.json"
)
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
  assert_true(
    lua_t.dir == t.dir and lua_t.label == t.label and lua_t.field == t.field,
    "schema.reference_types." .. id .. " fields match schema.json"
  )
  assert_true(
    vim.deep_equal(lua_t.body, t.body),
    "schema.reference_types." .. id .. " body matches schema.json"
  )
  assert_true(
    vim.deep_equal(lua_t.min_fields, t.min_fields),
    "schema.reference_types." .. id .. " min_fields matches schema.json"
  )
end
assert_true(
  vim.deep_equal(schema.status_next, schema_json.status_next),
  "schema.status_next matches schema.json"
)
assert_true(
  vim.deep_equal(schema.scene_field_defs, schema_json.scene_field_defs),
  "schema.scene_field_defs matches schema.json"
)
assert_true(
  vim.deep_equal(schema.chapter_field_defs, schema_json.chapter_field_defs),
  "schema.chapter_field_defs matches schema.json"
)
assert_true(vim.deep_equal(schema.enums, schema_json.enums), "schema.enums matches schema.json")
assert_true(
  vim.deep_equal(schema.diagnostics, schema_json.diagnostics),
  "schema.diagnostics matches schema.json"
)

-- A folder outside the built-in types is still a first-class reference type.
local codex_project = vim.fn.tempname()
vim.fn.mkdir(codex_project .. "/references/creatures", "p")
vim.fn.mkdir(codex_project .. "/chapters", "p")
vim.fn.writefile({
  "---",
  "names:",
  "  - Gr'hall",
  "---",
  "",
  "## Gr'hall",
  "",
  "- **Notes:** ",
}, codex_project .. "/references/creatures/grhall.md")
vim.fn.writefile(
  { "# Chapter 1", "## S1", "Gr'hall lurks here." },
  codex_project .. "/chapters/01.md"
)
local codex_prj = project.paths_for(codex_project, true)
local refs = index.references(codex_prj)
assert_true(
  refs["creatures"] ~= nil and #refs["creatures"] == 1,
  "arbitrary references/creatures folder is indexed"
)
assert_true(
  schema.type_field("creatures") == "creatures",
  "custom type links into a folder-named field"
)
assert_true(schema.type_label("creatures") == "Creatures", "custom type gets a derived label")
local detect = require("storyteller.detect")
local sugs = detect.detect_scene(index.scenes(codex_prj)[1], codex_prj)
assert_true(
  #sugs == 1 and sugs[1].type == "creatures",
  "detection yields suggestions for custom types"
)
detect.link(index.scenes(codex_prj)[1], sugs[1].reference)
local sc = index.scenes(codex_prj)[1]
local after = table.concat(vim.fn.readfile(sc.path), "\n")
assert_true(
  after:find("creatures:\n  %- Gr'hall") ~= nil,
  "custom type links into its folder-named field"
)
vim.fn.delete(codex_project, "rf")

-- Runtime schema merge: project layers override, delete, and add to defaults.
local schema_proj = vim.fn.tempname()
vim.fn.mkdir(schema_proj .. "/.storyteller", "p")
vim.fn.writefile({
  "{",
  "  \"reference_types\": { \"item\": null },",
  "  \"enums\": { \"moods\": [\"tense\", \"calm\"] },",
  "  \"diagnostics\": { \"unknown_field\": false }",
  "}",
}, schema_proj .. "/.storyteller/schema.json")
local loaded = schema.load(schema_proj)
assert_true(loaded.reference_types.item == nil, "project schema deletes the item type")
assert_true(vim.deep_equal(loaded.enums.moods, { "tense", "calm" }), "project schema adds an enum")
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
local faction_json = vim.json.encode({
  reference_types = { faction = { dir = "factions", label = "Faction", field = "factions" } },
})
local faction_schema = faction_json
vim.fn.writefile({ faction_schema }, toml_proj .. "/config/schema.json")
vim.fn.writefile(
  { "[storyteller]", "schema = \"config/schema.json\"" },
  toml_proj .. "/.storyteller.toml"
)
local toml_loaded = schema.load(toml_proj)
assert_true(toml_loaded.reference_types.faction ~= nil, ".storyteller.toml points at a schema")
assert_true(schema.type_field("factions") == "factions", "custom faction type resolves its field")
assert_true(schema.type_label("factions") == "Faction", "custom faction type gets its label")
vim.fn.delete(toml_proj, "rf")

-- --- Annotations: stripped from compile, collected for review ----------------

vim.fn.writefile({
  "# Chapter 1",
  "",
  "## Scene 1",
  "",
  "%%fix this pacing%%",
  "Prose with an %%inline note%% inside it.",
  "Clean prose line.",
}, chapter)
local ann = compile.annotations(prj)
assert_true(#ann == 2, "annotations collects block and inline notes")
local stripped = compile.strip_metadata(vim.fn.readfile(chapter))
local joined_stripped = table.concat(stripped, "\n")
assert_true(
  joined_stripped:find("fix this pacing", 1, true) == nil,
  "block annotation is stripped from compile"
)
assert_true(
  joined_stripped:find("inline note", 1, true) == nil,
  "inline annotation is stripped from compile"
)
assert_true(
  joined_stripped:find("Prose with an  inside it") ~= nil,
  "prose around inline annotation survives"
)

-- --- Compile presets filter scenes by status ---------------------------------

vim.fn.writefile({
  "# Chapter 1",
  "",
  "## Kept scene",
  "```yaml",
  "storyteller: scene",
  "status: done",
  "```",
  "kept prose here.",
  "",
  "## Dropped scene",
  "```yaml",
  "storyteller: scene",
  "status: outline",
  "```",
  "dropped prose here.",
}, chapter)
-- The `.storyteller` marker is a file here; a directory also satisfies the
-- marker check, so swap it out to host compile.json.
vim.fn.delete(prj.root .. "/.storyteller")
vim.fn.mkdir(prj.root .. "/.storyteller", "p")
vim.fn.writefile({}, prj.root .. "/.storyteller/marker")
vim.fn.writefile(
  { "{ \"include_statuses\": [\"done\"] }" },
  prj.root .. "/.storyteller/compile.json"
)
vim.fn.writefile(
  { "{ \"include_statuses\": [\"done\"] }" },
  prj.root .. "/.storyteller/compile.json"
)
local ms = table.concat(compile.manuscript(prj), "\n")
assert_true(ms:find("kept prose here", 1, true) ~= nil, "preset keeps included statuses")
assert_true(ms:find("dropped prose here", 1, true) == nil, "preset drops excluded statuses")
vim.fn.delete(prj.root .. "/.storyteller/compile.json")

-- --- Scene reordering --------------------------------------------------------

-- Earlier sections left 01.md loaded with unsaved edits; start from scratch.
do
  local stale = vim.fn.bufnr(chapter)
  if stale ~= -1 then
    vim.api.nvim_buf_delete(stale, { force = true })
  end
end
local reorder = require("storyteller.reorder")
vim.fn.writefile({
  "# Chapter 1",
  "",
  "## First",
  "",
  "first prose.",
  "",
  "## Second",
  "",
  "second prose.",
  "",
}, chapter)
index.invalidate()
local two_scenes = {}
for _, rs in ipairs(index.scenes(prj)) do
  if rs.path == chapter then
    two_scenes[#two_scenes + 1] = rs
  end
end
assert_true(
  #two_scenes == 2 and two_scenes[1].title == "First",
  "reorder fixture indexes two scenes"
)
reorder.swap_in_file(chapter, two_scenes[1].start_line, two_scenes[2].start_line)
local swapped = table.concat(vim.fn.readfile(chapter), "\n")
assert_true(
  swapped:find("## Second") ~= nil and swapped:find("## Second") < swapped:find("## First"),
  "swap_in_file reorders scenes"
)
assert_true(swapped:find("second prose%.") ~= nil, "scene body travels with its heading")

-- Moving a scene to another chapter.
local move_target = tmp .. "/chapters/03_move.md"
vim.fn.writefile({ "# Chapter 3", "", "## Other", "", "other prose.", "" }, move_target)
index.invalidate()
local across = index.scenes(prj)
local moving, staying
for _, mv in ipairs(across) do
  if mv.path == move_target then
    staying = mv
  elseif mv.path == chapter and mv.title == "Second" then
    moving = mv
  end
end
reorder.move_to_file(moving, staying.path, staying.start_line, "before")
local moved_file = table.concat(vim.fn.readfile(move_target), "\n")
local second_at = moved_file:find("## Second")
assert_true(
  second_at ~= nil and second_at < moved_file:find("## Other"),
  "move_to_file inserts before anchor"
)
assert_true(moved_file:find("second prose%.") ~= nil, "moved scene keeps its body")
local ch1_after = table.concat(vim.fn.readfile(chapter), "\n")
assert_true(
  ch1_after:find("## Second", 1, true) == nil,
  "moved scene is removed from source chapter"
)

-- --- Collections --------------------------------------------------------------

local collections = require("storyteller.collections")
vim.fn.writefile({
  "# Chapter 1",
  "",
  "## Drafted",
  "```yaml",
  "storyteller: scene",
  "status: draft",
  "tags:",
  "  - war",
  "```",
  "draft text.",
  "",
  "## Finished",
  "```yaml",
  "storyteller: scene",
  "status: done",
  "```",
  "done text.",
  "",
}, chapter)
index.invalidate()
assert_true(collections.save(prj, "War drafts", "status:draft tag:war"), "collection saves")
local found = collections.list(prj)
assert_true(#found == 1 and found[1].name == "War drafts", "collection lists by name")
local matched = collections.run(prj, found[1].query)
assert_true(
  #matched == 1 and matched[1].title == "Drafted",
  "collection query matches status and tag"
)
assert_true(#collections.run(prj, "Finished") == 1, "bare title token matches")
collections.delete(prj, "War drafts")
assert_true(#collections.list(prj) == 0, "collection deletes")

-- --- Notes: markdown-file-backed annotations ---------------------------------

local notes = require("storyteller.notes")
vim.fn.mkdir(prj.root .. "/notes", "p")
vim.fn.writefile({
  "# Annotations",
  "",
  "## Fix the pacing",
  "",
  "```yaml",
  "storyteller: note",
  "status: open",
  "file: chapters/01.md",
  "line: 5",
  "created: 2026-08-21",
  "```",
  "",
  "> first prose.",
  "",
  "The reveal comes too late.",
  "",
  "## Already handled",
  "",
  "```yaml",
  "storyteller: note",
  "status: resolved",
  "file: chapters/01.md",
  "line: 9",
  "created: 2026-08-20",
  "```",
}, prj.root .. "/notes/annotations.md")
local parsed_notes = notes.list(prj)
assert_true(#parsed_notes == 2, "notes parses both entries")
assert_true(
  parsed_notes[1].title == "Fix the pacing" and parsed_notes[1].quote == "first prose.",
  "notes parse title and quote"
)
assert_true(parsed_notes[1].body[1] == "The reveal comes too late.", "notes keep their body text")
assert_true(parsed_notes[2].status == "resolved", "notes read status")

notes.toggle_status(prj, parsed_notes[1])
local toggled = notes.list(prj)
assert_true(
  toggled[1].status == "resolved" and toggled[2].status == "resolved",
  "note status toggles in place"
)
assert_true(
  toggled[1].quote == "first prose." and toggled[1].body[1] == "The reveal comes too late.",
  "toggle preserves quote and body"
)
notes.toggle_status(prj, toggled[1])

-- Capture appends a well-formed entry pointing at the source.
vim.cmd("edit! " .. vim.fn.fnameescape(chapter))
vim.api.nvim_win_set_cursor(0, { 5, 0 })
local captured = notes.capture(prj, "Check this line")
assert_true(
  captured ~= nil and captured.file == vim.fn.fnamemodify(chapter, ":."),
  "capture records the source file"
)
assert_true(captured.line == 5, "capture records the source line")
local after_capture = notes.list(prj)
assert_true(#after_capture == 3, "capture appends to the notes document")
assert_true(
  after_capture[#after_capture].title == "Check this line",
  "capture uses the given title"
)

-- Jump lands on the quoted text even when line numbers drifted.
local jumped_ok = false
notes.jump({ file = chapter, line = 100, quote = "second prose." })
jumped_ok = vim.api.nvim_win_get_cursor(0)[1] < 100
assert_true(jumped_ok, "jump relocates via quoted text when lines drift")

-- Delete removes exactly one entry.
local before_delete = #notes.list(prj)
assert_true(notes.delete(prj, after_capture[#after_capture]), "delete removes an entry")
assert_true(#notes.list(prj) == before_delete - 1, "delete leaves other entries intact")

-- --- Fountain export ----------------------------------------------------------

local fountain_path = require("storyteller.import").export_fountain(prj)
assert_true(
  fountain_path ~= nil and vim.loop.fs_stat(fountain_path) ~= nil,
  "fountain export writes a file"
)
local fountain = table.concat(vim.fn.readfile(fountain_path), "\n")
assert_true(fountain:find(".Drafted", 1, true) ~= nil, "scenes become forced fountain headings")
assert_true(fountain:find("draft text", 1, true) ~= nil, "fountain keeps prose")
assert_true(fountain:find("storyteller: scene", 1, true) == nil, "fountain strips metadata")

-- --- RTF stripping (Scrivener import path) ------------------------------------

local importer = require("storyteller.import")
local rtf_text = importer.rtf_to_text(
  "{\\rtf1\\ansi{\\fonttbl{\\f0 Helvetica;}}\\par Hello \\b world\\b0\\par second line}"
)
assert_true(
  rtf_text[1] == "Hello world" and rtf_text[2] == "second line",
  "rtf_to_text extracts plain lines"
)

-- --- Snapshot diff helpers ------------------------------------------------------

local parsed_snap = snapshot.parse("abc1234 2026-08-21 manual — checkpoint")
assert_true(
  parsed_snap and parsed_snap.hash == "abc1234" and parsed_snap.date == "2026-08-21",
  "snapshot.parse splits list lines"
)

-- --- Lazy-load stub registers :Story before setup -------------------------------

-- plugin/ scripts are only sourced on startup; simulate a lazy loader by
-- sourcing the stub directly, then verify the command exists.
pcall(vim.api.nvim_del_user_command, "Story")
vim.cmd("source " .. vim.fn.fnamemodify(vim.fn.getcwd(), ":p") .. "/plugin/storyteller.lua")
assert_true(vim.fn.exists(":Story") ~= 0, ":Story exists without explicit setup()")

-- --- Relations: parsing, graph, layout, grid ---------------------------------

local relations = require("storyteller.relations")
local card_lines = {
  "---",
  "names:",
  "  - Penelope",
  "relations:",
  "  - { to: Odysseus, kind: spouse }",
  "  - to: Telemachus",
  "    kind: parent",
  "  - weaver: loom",
  "---",
  "",
  "## Penelope",
}
local parsed_rels = relations.parse_card_relations(card_lines)
assert_true(#parsed_rels == 3, "relations parses flow maps, block maps, and shorthand")
assert_true(
  parsed_rels[1].to == "Odysseus" and parsed_rels[1].kind == "spouse",
  "flow-map relation parses"
)
assert_true(
  parsed_rels[2].to == "Telemachus" and parsed_rels[2].kind == "parent",
  "block-map relation parses"
)
assert_true(
  parsed_rels[3].to == "loom" and parsed_rels[3].kind == "weaver",
  "shorthand relation parses"
)
assert_true(
  #relations.parse_card_relations({ "---", "names:", "  - X", "---" }) == 0,
  "cards without relations parse empty"
)

-- Edge editing round-trip on a real file.
local rel_card = tmp .. "/references/characters/penelope.md"
vim.fn.mkdir(tmp .. "/references/characters", "p")
vim.fn.writefile(card_lines, rel_card)
assert_true(relations.add_edge(rel_card, "Argos", "loves"), "add_edge inserts into existing block")
local after_add = table.concat(vim.fn.readfile(rel_card), "\n")
assert_true(after_add:find("to: Argos, kind: loves") ~= nil, "added edge is present")
assert_true(after_add:find("names:") ~= nil, "add_edge preserves other frontmatter")
assert_true(
  relations.remove_edge(rel_card, "Argos", "loves"),
  "remove_edge drops the matching line"
)
local after_remove = table.concat(vim.fn.readfile(rel_card), "\n")
assert_true(after_remove:find("Argos", 1, true) == nil, "removed edge is gone")

-- Graph build over the project's cards.
vim.fn.writefile({
  "---",
  "names:",
  "  - Odysseus",
  "relations:",
  "  - { to: Penelope, kind: spouse }",
  "---",
  "",
  "## Odysseus",
}, tmp .. "/references/characters/odysseus_rel.md")
index.invalidate()
local graph = relations.build(prj)
assert_true(#graph.nodes >= 2, "graph builds nodes from reference cards")
assert_true(#graph.edges >= 2, "graph builds edges from card relations")
local circle_pos = relations.layout(graph)
assert_true(circle_pos["Odysseus"] ~= nil, "layout positions every node")
local rendered_grid = relations.render_grid(graph, { width = 40, height = 14, focus = "Odysseus" })
assert_true(#rendered_grid.lines == 14, "grid renders at the requested height")
assert_true(rendered_grid.rects["Odysseus"] ~= nil, "grid records node rects")
-- Focused node's rows carry the accent highlight somewhere.
local has_accent = false
for _, line in ipairs(rendered_grid.lines) do
  for _, seg in ipairs(line.segments or {}) do
    if seg.hl == "StorytellerKey" then
      has_accent = true
    end
  end
end
assert_true(has_accent, "focused node is highlighted in the grid")

-- --- Projections (docs/projections.md) ------------------------------------------

local projections = require("storyteller.projections")

-- A fresh project so projection tests see exactly the scenes they create.
local ptmp = vim.fn.tempname()
vim.fn.mkdir(ptmp .. "/chapters", "p")
vim.fn.writefile({}, ptmp .. "/.storyteller")
local pprj = project.paths_for(ptmp, true)

local ch_a = ptmp .. "/chapters/a.md"
local ch_b = ptmp .. "/chapters/b.md"
vim.fn.writefile({
  "# Chapter A",
  "",
  "## First scene",
  "```yaml",
  "storyteller: scene",
  "status: draft",
  "pov: Odysseus",
  "day: 1",
  "```",
  "prose one two three four five",
  "",
  "## Second scene",
  "```yaml",
  "storyteller: scene",
  "status: outline",
  "pov: Athena",
  "```",
  "prose six seven eight nine ten eleven twelve",
}, ch_a)
vim.fn.writefile({
  "# Chapter B",
  "",
  "## Third scene",
  "```yaml",
  "storyteller: scene",
  "status: revision",
  "location: Ithaca",
  "```",
  "prose thirteen fourteen fifteen sixteen",
}, ch_b)
index.invalidate()

local board = projections.render("corkboard", pprj)
assert_true(board ~= nil and #board.lines > 6, "corkboard renders cards")
assert_true(board.text:find("## First scene", 1, true) ~= nil, "card headers carry the title")
assert_true(
  board.text:find("file: chapters/a.md", 1, true) ~= nil,
  "cards carry an editable file address"
)
assert_true(board.text:find("status: draft", 1, true) ~= nil, "field lines render")
local again = projections.render("corkboard", pprj)
assert_true(again.text == board.text, "rendering is deterministic")

-- Field edit: change status on the first card.
local edited = vim.deepcopy(board.lines)
for i, ln in ipairs(edited) do
  if ln == "status: draft" then
    edited[i] = "status: done"
    break
  end
end
local applied, err = projections.commit("corkboard", pprj, board.lines, edited)
assert_true(applied and applied >= 1, "field edit applies: " .. tostring(err))
index.invalidate()
local first_scene
for _, psc in ipairs(index.scenes(pprj)) do
  if psc.title == "First scene" then
    first_scene = psc
  end
end
assert_true(first_scene.meta.status == "done", "status edit reaches scene YAML")

-- Reorder: move the third scene to the front of the board.
local board2 = projections.render("corkboard", pprj)
local reordered = {}
for _, ln in ipairs(board2.lines) do
  reordered[#reordered + 1] = ln
end
-- Cut the third card block and paste it before the first, retargeting its
-- file: line to chapter A (the oil-style cross-file move).
local heads = {}
for i, ln in ipairs(reordered) do
  if ln:match("^## ") then
    heads[#heads + 1] = i
  end
end
assert_true(#heads == 3, "three cards render")
-- Card 3 spans header .. trailing blank (header + file + fields + words + blank).
local card_end = #reordered
for n = heads[3] + 1, #reordered do
  if reordered[n]:match("^## ") then
    card_end = n - 1
    break
  end
end
while reordered[card_end] == "" do
  card_end = card_end - 1
end
local third_block = {}
for i = heads[3], card_end do
  third_block[#third_block + 1] = reordered[i]
end
for i, l in ipairs(third_block) do
  third_block[i] = l:gsub("^file: chapters/b%.md$", "file: chapters/a.md")
end
local cut = {}
for i = 1, heads[3] - 1 do
  cut[#cut + 1] = reordered[i]
end
for i = card_end + 1, #reordered do
  cut[#cut + 1] = reordered[i]
end
local moved = { cut[1], "" }
for _, l in ipairs(third_block) do
  moved[#moved + 1] = l
end
moved[#moved + 1] = ""
for i = 2, #cut do
  moved[#moved + 1] = cut[i]
end
local applied2, err2 = projections.commit("corkboard", pprj, board2.lines, moved)
assert_true(applied2 and applied2 >= 1, "cross-file reorder applies: " .. tostring(err2))
index.invalidate()
local order = {}
for _, psc in ipairs(index.scenes(pprj)) do
  order[#order + 1] = psc.title
end
assert_true(
  order[1] == "Third scene",
  "moved scene now opens the story: " .. table.concat(order, ",")
)
assert_true(order[4] == nil and #order == 3, "no scenes lost in reorder")

-- Round trip: the moved scene now renders under its new file address.
local board3 = projections.render("corkboard", pprj)
assert_true(
  board3.text:find("file: chapters/a.md", 1, true) ~= nil
    and board3.text:find("## Third scene", 1, true) ~= nil,
  "round trip keeps identity"
)

-- Deletion is rejected, not guessed at.
local removed = {}
local skipped = false
for _, ln in ipairs(board3.lines) do
  if not (ln:match("^## ") and ln:find("Third scene", 1, true) and not skipped) then
    removed[#removed + 1] = ln
  elseif ln:match("^## ") then
    skipped = true
  end
end
local ok_del, err_del = projections.commit("corkboard", pprj, board3.lines, removed)
assert_true(ok_del == nil, "card deletion is rejected")

-- Timeline: editing the day cell retimes the scene.
local tl = projections.render("timeline", pprj)
local tl_edited = vim.deepcopy(tl.lines)
local tl_touched = false
for i, ln in ipairs(tl_edited) do
  if not tl_touched and ln:find("| First scene", 1, true) then
    tl_edited[i] = (ln:gsub("^%s*%S+", "7", 1))
    tl_touched = true
  end
end
assert_true(tl_touched, "timeline row for First scene found")
local applied3, err3 = projections.commit("timeline", pprj, tl.lines, tl_edited)
assert_true(applied3 and applied3 >= 1, "timeline day edit applies: " .. tostring(err3))
index.invalidate()
for _, psc in ipairs(index.scenes(pprj)) do
  if psc.title == "First scene" then
    assert_true(tonumber(psc.meta.day) == 7, "day edit reaches scene YAML")
  end
end

-- Synopsis: prose under a scene heading writes the synopsis field.
local syn = projections.render("synopsis", pprj)
local syn_edited = vim.deepcopy(syn.lines)
for i, ln in ipairs(syn_edited) do
  if ln:match("^## ") and ln:find("Second scene", 1, true) then
    table.insert(syn_edited, i + 1, "Athena watches from the rigging.")
    break
  end
end
local applied4, err4 = projections.commit("synopsis", pprj, syn.lines, syn_edited)
assert_true(applied4 and applied4 >= 1, "synopsis edit applies: " .. tostring(err4))
index.invalidate()
for _, psc in ipairs(index.scenes(pprj)) do
  if psc.title == "Second scene" then
    assert_true(
      tostring(psc.meta.synopsis):find("rigging", 1, true) ~= nil,
      "synopsis prose reaches scene YAML"
    )
  end
end

-- Removing prose removes the field (vim.NIL semantics, no NUL corruption).
local syn2 = projections.render("synopsis", pprj)
local syn_removed = {}
for _, ln in ipairs(syn2.lines) do
  if ln ~= "Athena watches from the rigging." then
    syn_removed[#syn_removed + 1] = ln
  end
end
local applied6, err6 = projections.commit("synopsis", pprj, syn2.lines, syn_removed)
assert_true(applied6 and applied6 >= 1, "synopsis removal applies: " .. tostring(err6))
index.invalidate()
for _, psc in ipairs(index.scenes(pprj)) do
  if psc.title == "Second scene" then
    assert_true(psc.meta.synopsis == nil, "synopsis removal clears the YAML field")
  end
end

-- Metasheet: bulk cell edit.
local sheet = projections.render("metasheet", pprj)
local sheet_edited = vim.deepcopy(sheet.lines)
for i, ln in ipairs(sheet_edited) do
  if ln:find("Third scene", 1, true) then
    sheet_edited[i] = ln:gsub("| revision ", "| done     ")
    break
  end
end
local applied5, err5 = projections.commit("metasheet", pprj, sheet.lines, sheet_edited)
assert_true(applied5 and applied5 >= 1, "metasheet cell edit applies: " .. tostring(err5))
index.invalidate()
for _, psc in ipairs(index.scenes(pprj)) do
  if psc.title == "Third scene" then
    assert_true(psc.meta.status == "done", "metasheet edit reaches scene YAML")
  end
end

-- Storyboard buffer machinery loads.
require("storyteller.ui.storyboard")
assert_true(type(require("storyteller.ui.storyboard").open) == "function", "storyboard host loads")

-- Storyboard extmark styling: bands, status colors, and live repaint.
local board_hl = require("storyteller.ui.board_hl")
do
  local sbuf = require("storyteller.ui.storyboard").open("corkboard", pprj)
  local marks = vim.api.nvim_buf_get_extmarks(sbuf, board_hl.namespace, 0, -1, { details = true })
  assert_true(#marks > 5, "storyboard painter applies extmarks")
  local surface_on_header = false
  for _, m in ipairs(marks) do
    if m[2] == 2 and m[4].hl_group == "StorytellerSurface" then
      surface_on_header = true
    end
  end
  assert_true(surface_on_header, "card headers carry the surface band")

  -- Editing a status line repaints with the new status color.
  local board_lines = vim.api.nvim_buf_get_lines(sbuf, 0, -1, false)
  for i, ln in ipairs(board_lines) do
    if ln:match("^status:") then
      vim.api.nvim_buf_set_lines(sbuf, i - 1, i, false, { "status: revision" })
      break
    end
  end
  board_hl.paint(sbuf, "corkboard")
  local revised = false
  marks = vim.api.nvim_buf_get_extmarks(sbuf, board_hl.namespace, 0, -1, { details = true })
  for _, m in ipairs(marks) do
    if m[4].hl_group == "StorytellerRevision" then
      revised = true
    end
  end
  assert_true(revised, "status values carry their status color")
end

vim.fn.delete(ptmp, "rf")

-- === Schema v1.3 parity: shelving exclusion + list-field round-trips ===
do
  local stmp = vim.fn.tempname()
  vim.fn.mkdir(stmp .. "/chapters", "p")
  vim.fn.mkdir(stmp .. "/references/characters", "p")
  vim.fn.writefile({}, stmp .. "/.storyteller")
  vim.fn.writefile({
    "# Chapter One",
    "",
    "## Kept",
    "",
    "```yaml",
    "storyteller: scene",
    "day: 1",
    "plotlines:",
    "  - Telemachy",
    "also:",
    "  - { timeline: Past, at: 40 }",
    "events:",
    "  - The Assembly",
    "```",
    "",
    "Five words of kept prose here.",
    "",
    "## Shelved",
    "",
    "```yaml",
    "storyteller: scene",
    "status: unused",
    "day: 2",
    "```",
    "",
    "Ten words that must not be counted at all.",
    "",
  }, stmp .. "/chapters/01.md")
  vim.fn.writefile({
    "---",
    "status: unused",
    "---",
    "",
    "# Chapter Two",
    "",
    "## The cave",
    "",
    "prose words words words",
  }, stmp .. "/chapters/02-cave.md")

  local sprj = project.resolve(stmp)
  local chapters = index.chapters(sprj)
  assert_true(#chapters == 2, "shelved chapter still indexes for editing")
  assert_true(chapters[2].status == "unused", "chapter frontmatter status is surfaced")

  -- Compilation excludes the shelved scene and the whole unused chapter.
  local ms = compile.manuscript(sprj)
  local text = table.concat(ms, "\n")
  assert_true(text:match("Kept") ~= nil, "kept scene compiles")
  assert_true(text:match("Shelved") == nil, "unused scene is excluded from compilation")
  assert_true(text:match("The cave") == nil, "unused chapter is excluded from compilation")

  -- Word totals skip shelved work.
  assert_true(index.chapter_words(chapters[1]) == 6, "unused scenes stay out of chapter word totals")
  assert_true(index.chapter_words(chapters[2]) == 0, "unused chapters contribute zero words")

  -- A4: new list fields round-trip as opaque strings (flow maps included).
  local sc = index.scenes(sprj)[1]
  assert_true(sc.meta.plotlines[1] == "Telemachy", "plotlines read as string lists")
  assert_true(
    sc.meta.also[1] == "{ timeline: Past, at: 40 }",
    "also entries stay opaque flow-map strings"
  )
  assert_true(sc.meta.events[1] == "The Assembly", "events read as string lists")
  local serde = require("storyteller.meta.serde")
  local out = serde.encode_map(sc.meta, { "day", "plotlines", "also", "events" })
  local joined = table.concat(out, "\n")
  assert_true(
    joined:match("%- %{ timeline: Past, at: 40 %}") ~= nil,
    "flow-map placement survives encode verbatim"
  )

  vim.fn.delete(stmp, "rf")
end

-- === Projection golden fixtures (docs/projections.md): ops applied to
-- fixture files must land byte-exact. Expectations are the Lua engine's
-- own output, frozen; the TUI asserts identical bytes via cargo test.
do
  local projections = require("storyteller.projections")
  local fixtures = vim.fn.glob("tests/projections/*.json", false, true)
  table.sort(fixtures)
  assert_true(#fixtures > 0, "projection golden fixtures exist")
  for _, path in ipairs(fixtures) do
    local okj, data = pcall(vim.json.decode, table.concat(vim.fn.readfile(path), "\n"))
    if not okj or type(data) ~= "table" or type(data.files) ~= "table" then
      assert_true(false, ("fixture %s decodes"):format(path))
    else
      local ftmp = vim.fn.tempname()
      for rel, content in pairs(data.files) do
        local full = ftmp .. "/" .. rel
        vim.fn.mkdir(vim.fn.fnamemodify(full, ":h"), "p")
        vim.fn.writefile(vim.split(content, "\n", { plain = true }), full)
      end
      vim.fn.writefile({}, ftmp .. "/.storyteller")
      local fprj = project.resolve(ftmp)
      local applied, err = projections.apply(data.name, fprj, data.ops)
      if not applied then
        assert_true(false, ("fixture %s applies: %s"):format(data.name, tostring(err)))
      else
        local all_ok = true
        for rel, want in pairs(data.expect) do
          local got = table.concat(vim.fn.readfile(ftmp .. "/" .. rel), "\n")
          if got ~= want then
            all_ok = false
            print(("MISMATCH %s in %s\n--- got ---\n%s\n--- want ---\n%s"):format(rel, data.name, got, want))
          end
        end
        assert_true(all_ok, ("fixture %s lands byte-exact (%d ops)"):format(data.name, applied))
      end
      vim.fn.delete(ftmp, "rf")
    end
  end
end

-- === Phase H: schema v1.2/v1.3 on the Neovim side ==========================

do
  -- H1: axis-aware timeline rows — primary declarations plus also: placements.
  local stmp = vim.fn.tempname()
  vim.fn.mkdir(stmp .. "/chapters", "p")
  vim.fn.mkdir(stmp .. "/references/timelines", "p")
  vim.fn.mkdir(stmp .. "/references/plotlines", "p")
  vim.fn.writefile({}, stmp .. "/.storyteller")
  vim.fn.writefile({
    "---",
    "order:",
    "  - Dawn",
    "  - Dusk",
    "unit: lamps",
    "---",
    "",
    "# Past",
  }, stmp .. "/references/timelines/Past.md")
  vim.fn.writefile({
    "---",
    "names:",
    "  - Telemachy",
    "stages:",
    "  - departure",
    "  - trials",
    "  - return",
    "---",
    "",
    "## The Telemachy",
  }, stmp .. "/references/plotlines/Telemachy.md")
  vim.fn.writefile({
    "# Chapter One",
    "",
    "## First",
    "",
    "```yaml",
    "storyteller: scene",
    "day: 2",
    "```",
    "",
    "words words words words words",
    "",
    "## Second",
    "",
    "```yaml",
    "storyteller: scene",
    "day: 1",
    "timeline: Past",
    "stage: trials",
    "plotlines:",
    "  - telemachy",
    "also:",
    "  - { timeline: Past, at: Dawn }",
    "```",
    "",
    "words words words words words",
    "",
    "## Third",
    "",
    "```yaml",
    "storyteller: scene",
    "day: 3",
    "stage: departure",
    "plotlines:",
    "  - Telemachy",
    "  - Ghostline",
    "```",
    "",
    "words words words words words",
  }, stmp .. "/chapters/01.md")

  local hprj = project.resolve(stmp)

  -- H1: main axis holds undeclared scenes only; Past axis the declared one
  -- plus the also-placement row (marked secondary, sharing its scene).
  local main_rows = index.timeline(hprj, "main")
  assert_true(#main_rows == 2, "main axis lists undeclared scenes")
  assert_true(main_rows[1].title == "First" and main_rows[2].title == "Third", "main sorts by day")
  local past_rows = index.timeline(hprj, "Past")
  assert_true(#past_rows == 2, "Past axis lists declared + also rows")
  local secondary_row, primary_row
  for _, r in ipairs(past_rows) do
    if r.timeline_secondary then
      secondary_row = r
    else
      primary_row = r
    end
  end
  assert_true(secondary_row ~= nil and secondary_row.timeline_value == "Dawn", "also placement renders as a secondary row with its own coordinate")
  assert_true(primary_row ~= nil and primary_row.title == "Second", "declared scene rides its axis")
  assert_true(secondary_row.timeline_rank == 1 and primary_row.timeline_numeric == 1, "ranks and numerics coexist on one axis")
  local axes = index.timeline_axes(hprj)
  assert_true(#axes == 2 and axes[1].name == "main" and axes[2].name == "Past", "axes list main first then cards")
  assert_true(axes[2].unit == "lamps" and #axes[2].order == 2, "axis card order/unit surface")

  -- Timeline projection sheet: secondary rows carry the read-only marker.
  local tl = require("storyteller.projections.timeline")
  local sheet = tl.render(hprj, "Past")
  local header = sheet.lines[1]
  assert_true(header == "# Timeline · Past · lamps", "sheet header names axis and unit")
  local parsed_sheet = tl.parse(sheet.lines)
  local marked = {}
  for _, rec in ipairs(parsed_sheet) do
    if rec.secondary then
      marked[#marked + 1] = rec
    end
  end
  assert_true(#marked == 1 and marked[1].day_cell == "Dawn", "parse strips the * marker but keeps it read-only")
  local ops_none = tl.diff(tl.parse(sheet.lines), tl.parse(sheet.lines))
  assert_true(#ops_none == 0, "unchanged sheet diffs to nothing")
  local refused = nil
  for _, ln in ipairs(sheet.lines) do
    if ln:find("^Dawn |") then
      refused = true
    end
  end
  assert_true(refused == nil, "secondary row renders under Dawn (setup sanity)")

  -- H2: plotline lanes with stages, regressions, uncovered stages.
  local lanes = index.plotlines(hprj)
  assert_true(#lanes == 1 and lanes[1].name == "The Telemachy", "track card becomes a lane")
  local lane = lanes[1]
  assert_true(#lane.stages == 3, "lane carries declared stages")
  assert_true(#lane.scenes == 2, "attached scenes join the lane via any alias")
  assert_true(lane.scenes[1].stage == "trials" and lane.scenes[1].regression == false, "first attachment never regresses")
  assert_true(lane.scenes[2].regression == true, "departure after trials flags a stage regression")
  assert_true(#lane.uncovered == 1 and lane.uncovered[1] == "return", "only the unreached stage is uncovered")

  -- Health gates: regression + uncovered stage + orphan plotline.
  local kinds = {}
  for _, f in ipairs(index.story_health(hprj)) do
    kinds[f.kind] = (kinds[f.kind] or 0) + 1
  end
  assert_true((kinds.stage_regression or 0) == 1, "health reports the stage regression")
  assert_true((kinds.uncovered_stage or 0) == 1, "health reports the uncovered stage")
  assert_true((kinds.orphan_plotline or 0) == 1, "health reports the orphan plotline name")

  -- H3: collections query keys.
  local collections = require("storyteller.collections")
  local by_plot = collections.run(hprj, "plotline:telem")
  assert_true(#by_plot == 2, "plotline: matches attached scenes")
  local by_stage = collections.run(hprj, "stage:trial")
  assert_true(#by_stage == 1 and by_stage[1].title == "Second", "stage: matches scene stages")
  local by_axis = collections.run(hprj, "timeline:past")
  assert_true(#by_axis == 1 and by_axis[1].title == "Second", "timeline: matches declared axis")

  -- H4: card fields unify bullets and heading sections; creation honors style.
  vim.fn.mkdir(stmp .. "/references/characters", "p")
  vim.fn.writefile({
    "---",
    "names:",
    "  - Elpenor",
    "---",
    "",
    "## Elpenor",
    "",
    "- **Role:** shipmate",
    "",
    "### Notes",
    "",
    "Fell off a roof.",
    "",
    "### role",
    "",
    "duplicate should lose",
  }, stmp .. "/references/characters/elpenor.md")
  local refs = index.references(hprj)
  local elpenor
  for _, r in ipairs(refs.characters or {}) do
    if r.name == "Elpenor" then
      elpenor = r
    end
  end
  assert_true(elpenor ~= nil, "heading-field card indexes")
  assert_true(elpenor.fields.role.value == "shipmate", "first occurrence wins across forms")
  assert_true(elpenor.fields.notes.value == "Fell off a roof.", "heading sections become fields")

  local capture = require("storyteller.capture")
  local bullet_card = table.concat(capture.card_lines("characters", "Test"), "\n")
  assert_true(bullet_card:match("%- %*%*Role:%*%*") ~= nil, "bullet style is the default")
  local schema_mod = require("storyteller.schema")
  local old_types = schema_mod.reference_types
  schema_mod.reference_types = {
    characters = { dir = "characters", label = "Character", field = "characters", body = { "Notes" } },
    locations = { dir = "locations", label = "Location", field = "locations", body = { "Notes", "History" }, style = "headings" },
  }
  local heading_card = table.concat(capture.card_lines("locations", "Ithaca"), "\n")
  schema_mod.reference_types = old_types
  assert_true(heading_card:match("### Notes") ~= nil, "headings style emits sections")
  assert_true(heading_card:match("%*%*Notes:%*%*") == nil, "headings style omits bullets")

  -- H3: applying a template plants a plotline card whose stages are its beats.
  local templates = require("storyteller.templates")
  local card_path = templates.plotline_card(hprj, {
    id = "Quest",
    name = "The Quest",
    description = "A departure and an abyss.",
    structure = { { children = { { title = "Call" }, { title = "Abyss" } } } },
  })
  assert_true(card_path ~= nil and card_path:find("references/plotlines", 1, true) ~= nil, "template plants a plotline card")
  local card_doc = meta.chapter(card_path)
  assert_true(card_doc.meta.stages[1] == "Call" and card_doc.meta.stages[2] == "Abyss", "stages sequence mirrors the beats")
  assert_true(templates.plotline_card(hprj, { id = "Quest", name = "The Quest", structure = { { children = { { title = "Call" } } } } }) == nil, "existing card is never overwritten")

  vim.fn.delete(stmp, "rf")
end

print(("RESULT: %d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
