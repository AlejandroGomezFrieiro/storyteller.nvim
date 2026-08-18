-- storyteller.workflow
-- Scene navigation plus derived continuity, revision, context, and discovery views.

local index = require("storyteller.index")
local project = require("storyteller.project")
local scene_data = require("storyteller.scene")
local pickers = require("storyteller.pickers")
local view = require("storyteller.view")

local M = {}

local function scenes(prj)
  return index.scenes(prj or project.current())
end

local function open(scene)
  vim.cmd("edit " .. vim.fn.fnameescape(scene.path))
  vim.api.nvim_win_set_cursor(0, { scene.start_line, 0 })
  vim.cmd("normal! zt")
end

local function current(prj)
  return scene_data.current(prj or project.current())
end

local function display(scene)
  local meta = scene_data.from_index(scene).meta
  return ("%s · %s · %s"):format(
    vim.fn.fnamemodify(scene.path, ":t:r"),
    scene.title or "(untitled)",
    meta.status or "outline"
  )
end

function M.pick(prj)
  prj = prj or project.current()
  if not prj then return end
  local entries = {}
  for _, scene in ipairs(scenes(prj)) do
    entries[#entries + 1] = { value = scene, display = display(scene) }
  end
  pickers.pick_list(entries, { prompt_title = "Story scenes", on_select = open })
end

function M.move(delta, prj)
  prj = prj or project.current()
  local active = current(prj)
  if not active then
    return M.pick(prj)
  end
  local all = scenes(prj)
  for i, scene in ipairs(all) do
    if scene.path == active.path and scene.start_line == active.start_line then
      local target = all[i + delta]
      if target then open(target) end
      return
    end
  end
end

local function matches(scene, filters)
  local meta = scene_data.from_index(scene).meta
  for key, expected in pairs(filters) do
    if key == "unfinished" then
      local body = table.concat(vim.list_slice(vim.fn.readfile(scene.path), scene.start_line, scene.end_line), "\n")
      if not body:find("%-%s*%[%s*%]") then return false end
    elseif key == "missing" then
      if meta[expected] and meta[expected] ~= "" then return false end
    elseif tostring(meta[key] or ""):lower() ~= expected:lower() then
      return false
    end
  end
  return true
end

function M.continuity(prj, filters)
  prj = prj or project.current()
  if not prj then return end
  filters = filters or {}
  local buf = view.open("continuity", prj)
  local lines = {
    "CONTINUITY",
    "<CR> open scene · R refresh · q close",
    "SCENE                              POV          LOCATION       TIME         STATUS",
  }
  local rows = {}
  for _, scene in ipairs(scenes(prj)) do
    if matches(scene, filters) then
      local meta = scene_data.from_index(scene).meta
      lines[#lines + 1] = ("%-34s %-12s %-14s %-12s %s"):format(
        (scene.title or ""):sub(1, 34),
        tostring(meta.pov or "?"):sub(1, 12),
        tostring(meta.location or "?"):sub(1, 14),
        tostring(meta.time or "?"):sub(1, 12),
        tostring(meta.status or "outline")
      )
      rows[#lines] = scene
    end
  end
  view.render(buf, lines)
  vim.b[buf].storyteller_continuity = { prj = prj, filters = filters, rows = rows }
  vim.keymap.set("n", "<CR>", function()
    local scene = vim.b[buf].storyteller_continuity.rows[vim.api.nvim_win_get_cursor(0)[1]]
    if scene then open(scene) end
  end, { buffer = buf, silent = true, desc = "Open scene" })
  vim.keymap.set("n", "R", function() M.continuity(prj, filters) end, { buffer = buf, silent = true, desc = "Refresh continuity" })
end

function M.revision(prj, base)
  prj = prj or project.current()
  if not prj then return end
  local changed = {}
  local args = base and { "git", "-C", prj.root, "diff", "--name-only", base .. "...HEAD" }
    or { "git", "-C", prj.root, "diff", "--name-only", "HEAD" }
  local files = vim.fn.systemlist(args)
  if vim.v.shell_error == 0 then
    for _, file in ipairs(files) do
      changed[prj.root .. "/" .. file] = true
    end
  end
  local buf = view.open("revision", prj)
  local lines = { "REVISION QUEUE", "<CR> open scene · R refresh · q close" }
  local rows = {}
  for _, scene in ipairs(scenes(prj)) do
    local meta = scene_data.from_index(scene).meta
    local body = table.concat(vim.list_slice(vim.fn.readfile(scene.path), scene.start_line, scene.end_line), "\n")
    local tasks = select(2, body:gsub("%-%s*%[%s*%]", ""))
    if meta.status == "revision" or tasks > 0 or changed[scene.path] then
      lines[#lines + 1] = ("[%s] %s · %d open task(s) · %s"):format(meta.status or "draft", scene.title or "", tasks, changed[scene.path] and "changed" or "unchanged")
      rows[#lines] = scene
    end
  end
  view.render(buf, lines)
  vim.b[buf].storyteller_revision = { rows = rows }
  vim.keymap.set("n", "<CR>", function()
    local scene = vim.b[buf].storyteller_revision.rows[vim.api.nvim_win_get_cursor(0)[1]]
    if scene then open(scene) end
  end, { buffer = buf, silent = true, desc = "Open revision scene" })
  vim.keymap.set("n", "R", function() M.revision(prj, base) end, { buffer = buf, silent = true, desc = "Refresh revision queue" })
end

function M.context(prj)
  prj = prj or project.current()
  local scene = current(prj)
  if not (prj and scene) then return end
  vim.cmd("vsplit")
  local buf = view.open("context", prj)
  local meta = scene_data.from_index(scene).meta
  local lines = {
    (scene.title or "SCENE"):upper(),
    "<CR> open reference · R refresh · q close",
    "",
    ("Status: %s | POV: %s | Location: %s"):format(meta.status or "outline", meta.pov or "?", meta.location or "?"),
    "",
    "BEAT",
    tostring(meta.beat or scene.inline.beat or "No beat recorded."),
    "",
    "GOAL / CONFLICT / OUTCOME",
    tostring(meta.goal or "—"),
    tostring(meta.conflict or "—"),
    tostring(meta.outcome or "—"),
  }
  view.render(buf, lines)
  vim.wo.winfixwidth = true
end

function M.idea(prj)
  prj = prj or project.current()
  local scene = current(prj)
  if not scene then return end
  vim.ui.input({ prompt = "Discovery idea: " }, function(value)
    if not value or value == "" then return end
    local lines = vim.fn.readfile(scene.path)
    table.insert(lines, (scene.end_line or #lines) + 1, "- [ ] IDEA: " .. value)
    vim.fn.writefile(lines, scene.path)
  end)
end

function M.discoveries(prj)
  prj = prj or project.current()
  if not prj then return end
  local buf = view.open("discoveries", prj)
  local lines = { "DISCOVERIES", "<CR> open scene · p promote to beat · R refresh · q close" }
  local rows = {}
  for _, scene in ipairs(scenes(prj)) do
    local body = vim.fn.readfile(scene.path)
    for line = scene.start_line, scene.end_line do
      local idea = (body[line] or ""):match("^%s*%-%s*%[%s*%]%s*IDEA:%s*(.+)$")
      if idea then
        lines[#lines + 1] = ("%s · %s"):format(scene.title or "", idea)
        rows[#lines] = { scene = scene, line = line, idea = idea }
      end
    end
  end
  view.render(buf, lines)
  vim.b[buf].storyteller_discoveries = { rows = rows }
  vim.keymap.set("n", "<CR>", function()
    local row = vim.b[buf].storyteller_discoveries.rows[vim.api.nvim_win_get_cursor(0)[1]]
    if row then open(row.scene) end
  end, { buffer = buf, silent = true, desc = "Open discovery scene" })
  vim.keymap.set("n", "p", function()
    local row = vim.b[buf].storyteller_discoveries.rows[vim.api.nvim_win_get_cursor(0)[1]]
    if not row then return end
    scene_data.update(row.scene, { beat = row.idea })
    local body = vim.fn.readfile(row.scene.path)
    for line, value in ipairs(body) do
      if value == "- [ ] IDEA: " .. row.idea then
        body[line] = "- [x] IDEA: " .. row.idea
        break
      end
    end
    vim.fn.writefile(body, row.scene.path)
    M.discoveries(prj)
  end, { buffer = buf, silent = true, desc = "Promote discovery to beat" })
  vim.keymap.set("n", "R", function() M.discoveries(prj) end, { buffer = buf, silent = true, desc = "Refresh discoveries" })
end

return M
