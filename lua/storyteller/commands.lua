-- storyteller.commands
-- A single `:Story` command with subcommand-style fargs and completion.
--
--   :Story                 open the dashboard
--   :Story outline         chapter outline
--   :Story compile[!]      editable continuous manuscript
--   :Story track           tracking dashboard
--   :Story export [fmt]    manuscript export
--   ...

local project = require("storyteller.project")
local index = require("storyteller.index")
local meta = require("storyteller.meta")
local compile = require("storyteller.compile")
local track = require("storyteller.track")
local snapshot = require("storyteller.snapshot")
local detect = require("storyteller.detect")
local references = require("storyteller.references")
local templates = require("storyteller.templates")
local pickers = require("storyteller.pickers")
local schema = require("storyteller.schema")

local M = {}

local HANDLERS = {}
local HELP = {}

local function register(name, desc, fn)
  HANDLERS[name] = fn
  HELP[name] = desc
end

local function need(prj)
  prj = prj or project.current()
  if not prj then
    vim.notify("[storyteller] Not in a storytelling project.", vim.log.levels.WARN)
    return nil
  end
  return prj
end

-- --- Navigation -------------------------------------------------------------

register("dashboard", "Open the dashboard", function()
  require("storyteller.ui.dashboard").open()
end)

register("outline", "Chapter outline with word counts", function(prj)
  require("storyteller.ui.views").outline(prj)
end)

register("scenes", "Pick a scene", function(prj)
  require("storyteller.ui.views").scenes(prj)
end)

register("next", "Next scene", function(prj)
  require("storyteller.ui.views").next(1, prj)
end)

register("prev", "Previous scene", function(prj)
  require("storyteller.ui.views").next(-1, prj)
end)

register("corkboard", "Scene cards (editable storyboard)", function(prj)
  require("storyteller.ui.storyboard").open("corkboard", prj)
end)

register("timeline", "Story chronology (editable storyboard)", function(prj, args)
  -- Optional axis: :Story timeline Past renders that axis's placements.
  local axis = type(args) == "table" and tostring(args[2] or "") or ""
  require("storyteller.ui.storyboard").open("timeline", prj, axis ~= "" and axis or nil)
end)

register("synopsis", "Synopsis outliner (editable storyboard)", function(prj)
  require("storyteller.ui.storyboard").open("synopsis", prj)
end)

register("metasheet", "Bulk scene metadata editor", function(prj)
  require("storyteller.ui.storyboard").open("metasheet", prj)
end)

register("relations", "Character relationship map", function(prj)
  prj = need(prj)
  if not prj then
    return
  end
  require("storyteller.ui.views").relations(prj)
end)

register("threads", "Plot setup and payoff planner", function(prj)
  require("storyteller.ui.views").threads(prj)
end)

register("health", "Review story health", function(prj)
  require("storyteller.ui.views").health(prj)
end)

register("resume", "Resume last scene", function(prj)
  require("storyteller.resume").open(prj)
end)

-- --- Metadata ---------------------------------------------------------------

register("meta", "Edit current scene metadata", function(prj)
  require("storyteller.ui.meta_form").edit(index.current_scene(prj))
end)

register("status", "Set/cycle current scene status", function(prj, args)
  local scene = index.current_scene(prj)
  if not scene then
    vim.notify("[storyteller] No scene under the cursor.", vim.log.levels.WARN)
    return
  end
  -- Prefer the LSP automation bus when a storyteller client is attached.
  local lsp = require("storyteller.lsp")
  if lsp.available() then
    local res = lsp.command("storyteller.statusCycle", { scene.path, (scene.start_line or 1) - 1 })
    if res and res.ok and res.edit then
      vim.lsp.util.apply_workspace_edit(res.edit)
      vim.notify("[storyteller] Scene status updated.", vim.log.levels.INFO)
      return
    end
  end
  local value = args[2]
  if value and schema.valid_status(value) then
    meta.scene_write(scene, { status = value })
  else
    local current = meta.field(scene, "status", "outline")
    meta.scene_write(scene, { status = schema.next_status(current) })
  end
  vim.notify("[storyteller] Scene status updated.", vim.log.levels.INFO)
end)

register("migrate", "Migrate inline metadata to scene YAML", function(prj)
  local file = vim.fn.expand("%:p")
  if file == "" then
    vim.notify("[storyteller] No file to migrate.", vim.log.levels.WARN)
    return
  end
  local n = meta.migrate(file)
  vim.notify(("[storyteller] Migrated %d scene(s)."):format(n), vim.log.levels.INFO)
end)

register("schema", "Inspect or write the merged schema", function(prj, args)
  prj = need(prj)
  if not prj then
    return
  end
  if args[2] == "write" then
    local path = schema.write(prj.root)
    vim.notify("[storyteller] Wrote " .. path, vim.log.levels.INFO)
  else
    vim.notify(vim.json.encode(schema.dump(prj.root)), vim.log.levels.INFO)
  end
end)

-- --- Compilation ------------------------------------------------------------

register("compile", "Editable continuous manuscript", function(prj, args, opts)
  compile.open(prj, { bang = opts and opts.bang or false })
end)

register("manuscript", "Write build/manuscript.md", function(prj)
  local path = compile.write_manuscript(prj)
  if path then
    vim.notify(("[storyteller] Wrote %s"):format(path), vim.log.levels.INFO)
  end
end)

-- --- Tracking ---------------------------------------------------------------

register("track", "Tracking dashboard", function(prj)
  require("storyteller.ui.views").track(prj)
end)

register("session", "Start/end a writing session", function(prj, args)
  if args[2] == "end" then
    track.session_end()
  else
    track.session_start()
  end
end)

register("snapshot", "Create a safety snapshot", function(prj, args)
  snapshot.snapshot(prj, args[2])
end)

register("snapshots", "List git snapshots", function(prj)
  prj = need(prj)
  if not prj then
    return
  end
  local snaps = snapshot.list(prj)
  if #snaps == 0 then
    vim.notify("[storyteller] No snapshots yet.", vim.log.levels.INFO)
    return
  end
  local entries = {}
  for _, s in ipairs(snaps) do
    entries[#entries + 1] = { value = s, display = tostring(s) }
  end
  pickers.pick_list(entries, {
    prompt_title = "Storyteller snapshots",
    on_select = function(s)
      snapshot.diff(prj, s)
    end,
    keys_note = "<CR> diff",
  })
end)

register("diff", "Diff working tree against a snapshot", function(prj, args)
  prj = need(prj)
  if not prj then
    return
  end
  local snaps = snapshot.list(prj)
  if #snaps == 0 then
    vim.notify("[storyteller] No snapshots yet.", vim.log.levels.INFO)
    return
  end
  if args[2] then
    for _, s in ipairs(snaps) do
      if s:find(args[2], 1, true) then
        snapshot.diff(prj, s)
        return
      end
    end
  end
  snapshot.diff(prj, nil)
end)

-- --- References -------------------------------------------------------------

register("references", "Browse reference cards", function(prj)
  references.panel(prj)
end)

register("capture", "Create a reference card from a selection", function(prj, args)
  require("storyteller.capture").run(prj, args[2])
end)

register("idea", "Capture an idea into research/ideas.md", function(prj)
  require("storyteller.ideas").capture(prj)
end)

register("ideas", "Open the ideas inbox", function(prj)
  require("storyteller.ideas").open(prj)
end)

register("detect", "Detect references", function(prj, args)
  prj = need(prj)
  if not prj then
    return
  end
  if args[2] == "scene" then
    local scene = index.current_scene(prj)
    if not scene then
      vim.notify("[storyteller] No scene under the cursor.", vim.log.levels.WARN)
      return
    end
    references.suggest(scene, prj)
    return
  end
  local results = detect.detect_project(prj)
  local total, linked = 0, 0
  for _, sugs in pairs(results) do
    total = total + #sugs
    for _, s in ipairs(sugs) do
      if s.confidence >= 0.9 then
        detect.link(s.scene, s.reference)
        linked = linked + 1
      end
    end
  end
  vim.notify(
    ("[storyteller] Detected %d suggestion(s); auto-linked %d confident match(es)."):format(
      total,
      linked
    ),
    vim.log.levels.INFO
  )
end)

-- --- Templating & export ----------------------------------------------------

local function template_pick(prj)
  local entries = templates.entries()
  if #entries == 0 then
    vim.notify("[storyteller] No story templates found.", vim.log.levels.WARN)
    return
  end
  pickers.pick_list(entries, {
    prompt_title = "Storyteller templates",
    on_select = function(entry)
      require("storyteller.ui.views").template_preview(prj, entry.id)
    end,
  })
end

register("template", "Apply a story structure", function(prj, args)
  if args[2] then
    require("storyteller.ui.views").template_preview(prj, args[2])
  else
    template_pick(prj)
  end
end)

register("export", "Export manuscript (docx/epub/pdf/smf)", function(prj, args)
  prj = need(prj)
  if not prj then
    return
  end
  if args[2] == "all" then
    local out = compile.export_all(prj, args[3])
    if out then
      vim.notify(("[storyteller] Exported %d chapter(s)."):format(#out), vim.log.levels.INFO)
    end
  else
    local out = compile.export(prj, args[2])
    if out then
      vim.notify(("[storyteller] Exported manuscript → %s"):format(out), vim.log.levels.INFO)
    end
  end
end)

-- --- Workspace / palette ----------------------------------------------------

register("workspace", "Toggle the binder+inspector workspace", function(prj)
  require("storyteller.ui.workspace").toggle(prj)
end)

-- Launch the ratatui cockpit inside a terminal buffer. Normal mode stays in
-- Neovim (j/k scrolls); press `i` to drive the TUI, `q` inside it to return.
register("tui", "Open the storyteller TUI dashboard", function(prj)
  prj = need(prj)
  if not prj then
    return
  end
  local bin = require("storyteller.config").bin("tui_bin")
  if not bin then
    vim.notify(
      "[storyteller] storyteller-tui not found (see :help storyteller-tui).",
      vim.log.levels.WARN
    )
    return
  end
  vim.cmd("enew")
  -- Theme parity: pass the editor's background plus any configured theme
  -- overrides (docs/tui-visual-plan.md §10).
  local cfg = require("storyteller.config").get()
  local argv = { bin, "--background", vim.o.background == "light" and "light" or "dark" }
  if cfg.tui_theme then
    table.insert(argv, "--theme")
    table.insert(argv, cfg.tui_theme)
  end
  if cfg.tui_glyphs then
    table.insert(argv, "--glyphs")
    table.insert(argv, cfg.tui_glyphs)
  end
  vim.fn.termopen(argv, { cwd = prj.root })
  vim.wo.winbar = "%#StorytellerTitle# Storyteller TUI %#StorytellerMuted i interact · q quits TUI"
end)

register("compose", "Distraction-free composition mode", function()
  require("storyteller.compose").toggle()
end)

-- --- Review -----------------------------------------------------------------

register("note", "Capture an annotation from the selection", function(prj, args)
  prj = need(prj)
  if not prj then
    return
  end
  local title = table.concat({ unpack(args, 2) }, " ")
  local entry = require("storyteller.notes").capture(prj, title ~= "" and title or nil)
  if entry then
    vim.notify("[storyteller] Note captured to notes/annotations.md.", vim.log.levels.INFO)
  end
end)

register("annotations", "Review annotations", function(prj)
  require("storyteller.ui.views").annotations(prj)
end)

register("collections", "Saved searches over scenes", function(prj)
  require("storyteller.ui.views").collections(prj)
end)

register("collect", "Run a one-off scene query", function(prj, args)
  prj = need(prj)
  if not prj then
    return
  end
  local query = table.concat({ unpack(args, 2) }, " ")
  if query == "" then
    vim.notify("[storyteller] Usage: :Story collect status:draft tag:war", vim.log.levels.WARN)
    return
  end
  require("storyteller.ui.views").collection_run(prj, { name = query, query = query })
end)

-- --- Migration --------------------------------------------------------------

register("import", "Import a Scrivener .scrivx project", function(prj, args)
  prj = need(prj)
  if not prj then
    return
  end
  local path = args[2]
  if not path or path == "" then
    vim.notify("[storyteller] Usage: :Story import /path/to/project.scrivx", vim.log.levels.WARN)
    return
  end
  local n = require("storyteller.import").import_scrivx(prj, vim.fn.expand(path))
  if n then
    vim.notify(
      ("[storyteller] Imported %d document(s) into chapters/."):format(n),
      vim.log.levels.INFO
    )
  end
end)

register("fountain", "Export the manuscript as Fountain", function(prj)
  prj = need(prj)
  if not prj then
    return
  end
  local path = require("storyteller.import").export_fountain(prj)
  if path then
    vim.notify("[storyteller] Wrote " .. path, vim.log.levels.INFO)
  end
end)

register("palette", "Command palette", function()
  local names = {}
  for name in pairs(HANDLERS) do
    names[#names + 1] = name
  end
  table.sort(names)
  local entries = {}
  for _, name in ipairs(names) do
    entries[#entries + 1] = { value = name, display = ("%s · %s"):format(name, HELP[name] or "") }
  end
  pickers.pick_list(entries, {
    prompt_title = "Storyteller commands",
    on_select = function(name)
      M.dispatch(project.current(), { name })
    end,
  })
end)

-- --- Dispatch & registration ------------------------------------------------

function M.dispatch(prj, args, opts)
  args = args or {}
  opts = opts or {}
  local name = args[1]
  if not name or name == "" then
    name = "dashboard"
  end
  if prj and prj.root then
    schema.load(prj.root)
  end
  local handler = HANDLERS[name]
  if not handler then
    vim.notify(("[storyteller] Unknown command: %s"):format(tostring(name)), vim.log.levels.ERROR)
    return
  end
  handler(prj, args, opts)
end

function M.complete(arglead, _cmdline, _cursorpos)
  local out = {}
  for name in pairs(HANDLERS) do
    if name:sub(1, #arglead) == arglead then
      out[#out + 1] = name
    end
  end
  table.sort(out)
  return out
end

function M.setup()
  if M._registered then
    return
  end
  vim.api.nvim_create_user_command("Story", function(opts)
    M.dispatch(project.current(), opts.fargs, { bang = opts.bang })
  end, {
    nargs = "*",
    bang = true,
    -- Acceptable from visual mode (`:'<,'>Story note`) so selection-based
    -- commands work; the range itself is ignored.
    range = true,
    complete = "customlist,v:lua.require'storyteller.commands'.complete",
    desc = "Storyteller commands",
  })
  M._registered = true
end

M.handlers = HANDLERS
M.help = HELP

return M
