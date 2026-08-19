-- storyteller.snapshot
-- Git-only rewrite-safe snapshots of the whole project. A snapshot is a git
-- commit whose subject begins `storyteller:snapshot`. No files or directories
-- are ever created; outside a git repository the user is prompted to `git init`.

local project = require("storyteller.project")

local M = {}

local function join(...)
  return table.concat({ ... }, "/")
end

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
    "git", "-C", prj.root, "log",
    "--format=%h %ad %s", "--date=short",
    "--grep=^storyteller:snapshot",
  })
  if vim.v.shell_error ~= 0 then
    return {}
  end
  return out
end

return M
