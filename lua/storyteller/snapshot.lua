-- storyteller.snapshot
-- Git-only rewrite-safe snapshots of the whole project. A snapshot is a git
-- commit whose subject begins `storyteller:snapshot`. No files or directories
-- are ever created; outside a git repository the user is prompted to `git init`.

local project = require("storyteller.project")

local M = {}

local function is_git(root)
  local ok = vim.fn.system({ "git", "-C", root, "rev-parse", "--git-dir" })
  return vim.v.shell_error == 0 and ok ~= ""
end

local function timestamp()
  return os.date("%Y%m%d-%H%M%S")
end

-- Take a snapshot. Returns { type = "git", id = ..., path = ... } or nil.
function M.snapshot(prj, message)
  prj = prj or project.current()
  if not prj then
    vim.notify("[storyteller] Not in a storytelling project.", vim.log.levels.WARN)
    return nil
  end

  if not is_git(prj.root) then
    local answer = vim.fn.confirm(
      "[storyteller] Snapshots require a git repository. Run `git init` here?",
      "&git init\n&Cancel",
      2
    )
    if answer == 1 then
      vim.fn.system({ "git", "-C", prj.root, "init" })
      vim.notify("[storyteller] Initialized a git repository.", vim.log.levels.INFO)
    else
      vim.notify("[storyteller] Snapshot cancelled (not a git repository).", vim.log.levels.INFO)
      return nil
    end
  end

  local msg = message and message ~= "" and message or "manual"
  local id = timestamp()
  vim.fn.system({ "git", "-C", prj.root, "add", "-A" })
  local subject = ("storyteller:snapshot %s — %s"):format(id, msg)
  local out = vim.fn.system({ "git", "-C", prj.root, "commit", "-m", subject })
  if vim.v.shell_error ~= 0 then
    local err = tostring(out)
    if err:find("nothing to commit") then
      vim.notify("[storyteller] Snapshot: no changes to commit.", vim.log.levels.INFO)
      return { type = "git", id = id, clean = true }
    end
    vim.notify("[storyteller] git snapshot failed: " .. err, vim.log.levels.ERROR)
    return nil
  end
  vim.notify(("[storyteller] Snapshot %s committed."):format(id), vim.log.levels.INFO)
  return { type = "git", id = id, path = prj.root }
end

-- List snapshots (git commits). Returns lines like `hash date subject`.
function M.list(prj)
  prj = prj or project.current()
  if not prj then
    return {}
  end
  if not is_git(prj.root) then
    return {}
  end
  local out = vim.fn.systemlist({
    "git",
    "-C",
    prj.root,
    "log",
    "--format=%h %ad %s",
    "--date=short",
    "--grep=^storyteller:snapshot",
  })
  if vim.v.shell_error ~= 0 then
    return {}
  end
  return out
end

-- Parse a `list()` line into { hash, date, message }.
function M.parse(line)
  local hash, date, msg = line:match("^(%S+)%s+(%S+)%s+(.*)$")
  return hash and { hash = hash, date = date, message = msg } or nil
end

-- Open a two-way diff of `file` between a snapshot commit and the working
-- tree. With no file, opens a summary view of everything changed since the
-- snapshot and lets <CR> drill into a per-file diff.
function M.diff(prj, snap_line, file)
  prj = prj or project.current()
  if not prj then
    vim.notify("[storyteller] Not in a storytelling project.", vim.log.levels.WARN)
    return
  end
  local s = type(snap_line) == "table" and snap_line or M.parse(snap_line or "")
  if not (s and s.hash) then
    -- Fall back to the most recent snapshot.
    local snaps = M.list(prj)
    s = snaps[1] and M.parse(snaps[1]) or nil
  end
  if not s then
    vim.notify("[storyteller] No snapshots to diff against.", vim.log.levels.WARN)
    return
  end

  if file then
    local rel = vim.fn.fnamemodify(file, ":.")
    if vim.fn.filereadable(prj.root .. "/" .. rel) ~= 1 then
      vim.notify("[storyteller] File no longer exists: " .. rel, vim.log.levels.WARN)
      return
    end
    local old = vim.fn.systemlist({ "git", "-C", prj.root, "show", ("%s:%s"):format(s.hash, rel) })
    if vim.v.shell_error ~= 0 then
      old = {}
    end
    vim.cmd("edit " .. vim.fn.fnameescape(prj.root .. "/" .. rel))
    local ob = vim.api.nvim_create_buf(false, true)
    vim.bo[ob].buftype = "nofile"
    vim.bo[ob].bufhidden = "wipe"
    vim.bo[ob].filetype = "markdown"
    pcall(vim.api.nvim_buf_set_name, ob, ("snapshot:%s:%s"):format(s.hash, rel))
    vim.api.nvim_buf_set_lines(ob, 0, -1, false, old)
    vim.cmd("vertical leftabove sbuffer " .. ob)
    vim.cmd("windo diffthis")
    return
  end

  -- Project-wide: list changed files since the snapshot.
  local changes = vim.fn.systemlist({ "git", "-C", prj.root, "diff", "--stat", s.hash, "--" })
  if #changes == 0 then
    vim.notify(
      ("[storyteller] No differences since %s (%s)."):format(s.hash, s.message or ""),
      vim.log.levels.INFO
    )
    return
  end
  require("storyteller.ui").view({
    name = "snapshot-diff",
    prj = prj,
    build = function()
      local lines = {
        {
          segments = {
            { text = " Snapshot diff ", hl = "StorytellerTitle" },
            {
              text = ("· %s · %s"):format(s.date or "", s.message or ""),
              hl = "StorytellerMuted",
            },
          },
        },
        { text = "" },
      }
      local sel = {}
      for _, c in ipairs(changes) do
        lines[#lines + 1] = { text = "  " .. c }
        local path = c:match("^%s*(%S+)")
        if path and c:find("|") then
          sel[#lines] = { file = path, snapshot = s }
        end
      end
      lines[#lines + 1] = { text = "" }
      lines[#lines + 1] = {
        segments = {
          { text = "<CR>", hl = "StorytellerKey" },
          { text = " open a two-way diff · ", hl = "StorytellerMuted" },
          { text = "q", hl = "StorytellerKey" },
          { text = " close", hl = "StorytellerMuted" },
        },
      }
      return { lines = lines, select = sel }
    end,
    on_select = function(data)
      if data and data.file then
        M.diff(prj, data.snapshot, prj.root .. "/" .. data.file)
      end
    end,
  })
end

return M
