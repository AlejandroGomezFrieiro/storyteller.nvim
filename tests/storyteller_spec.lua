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
local metadata = require("storyteller.metadata")
local target = require("storyteller.target")
local scrivenings = require("storyteller.scrivenings")
local export = require("storyteller.export")
local corkboard = require("storyteller.corkboard")
local index = require("storyteller.index")
local scene_data = require("storyteller.scene")

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

metadata.set(chapter, "status", "done")
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
assert_true(scene_data.ensure_id(parsed_scene) ~= nil, "scene receives stable ID when needed")

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
target.progress_append(prj)
vim.fn.writefile({ "# Chapter 1", words(20) }, chapter)
day = 2
target.progress_append(prj)
vim.fn.writefile({ "# Chapter 1", words(25) }, chapter)
day = 3
target.progress_append(prj)
os.date = original_date
local progress = vim.fn.readfile(tmp .. "/progress.log")
assert_true(progress[1] == "2026-01-01 10 10", "progress records first total")
assert_true(progress[2] == "2026-01-02 10 20", "progress records second-day delta")
assert_true(progress[3] == "2026-01-03 5 25", "progress records third-day delta")

-- Scrivenings must synchronize a clean source buffer after write-back.
vim.cmd("edit " .. vim.fn.fnameescape(chapter))
local source_buf = vim.api.nvim_get_current_buf()
local scriv_buf = scrivenings.open(prj)
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
local conflict_scriv = scrivenings.open(prj, { bang = true })
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

-- Commands from Storyteller scratch buffers retain their originating project.
local board = corkboard.open(prj)
assert_true(project.current().root == prj.root, "corkboard retains project context")
assert_true(scrivenings.open() ~= nil, "Scrivenings opens from corkboard context")

-- A fake pandoc copies its input so export output can be inspected without a
-- document toolchain. Per-chapter Storyteller metadata must not leak into it.
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
}, chapter)
local output = export.manuscript(prj, "docx")
local compiled = output and table.concat(vim.fn.readfile(output), "\n") or ""
assert_true(compiled:find("visible manuscript prose", 1, true) ~= nil, "export includes chapter prose")
assert_true(compiled:find("status: draft", 1, true) == nil, "export excludes chapter frontmatter")
local chapter_outputs = export.all(prj, "epub")
vim.env.PATH = old_path
assert_true(chapter_outputs and #chapter_outputs == 1, "export all creates one output per chapter")

require("storyteller").setup({ autocmds = false })
for _, name in ipairs({ "StoryScenePick", "StoryContinuity", "StoryRevision", "StoryContext", "StoryIdea", "StoryResume" }) do
  assert_true(vim.fn.exists(":" .. name) == 2, name .. " command is registered")
end

vim.fn.delete(tmp, "rf")
print(("RESULT: %d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
