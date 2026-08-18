-- storyteller.snapshot
-- Rewrite-safe snapshots of the whole project.
--
-- In a git repo: `git add -A` + a commit with a `storyteller:snapshot <msg>`
-- subject on the CURRENT branch (least surprising — no branch switching).
-- Outside git: copies chapters/ (+ outline, references) into
-- `build/snapshots/<timestamp>/`.

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

-- Take a snapshot. Returns { type = "git"|"copy", id = ..., path = ... }.
M.snapshot = function(prj, message)
  prj = prj or project.current()
  if not prj then
    vim.notify("[storyteller] Not in a storytelling project.", vim.log.levels.WARN)
    return nil
  end
  local msg = message and message ~= "" and message or "manual"
  local id = timestamp()

  if is_git(prj.root) then
    vim.fn.system({ "git", "-C", prj.root, "add", "-A" })
    local subject = ("storyteller:snapshot %s — %s"):format(id, msg)
    local out = vim.fn.system({ "git", "-C", prj.root, "commit", "-m", subject })
    if vim.v.shell_error ~= 0 then
      -- nothing to commit (clean tree) is not an error worth surfacing as one
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

  -- Non-git fallback: file copy.
  local dest = join(prj.build, "snapshots", id)
  vim.fn.mkdir(dest, "p")
  for _, dir in ipairs({ "chapters", "outline", "references", "treatment", "research" }) do
    local src = join(prj.root, dir)
    if vim.fn.isdirectory(src) == 1 then
      vim.fn.system({ "cp", "-r", src, dest })
    end
  end
  vim.notify(("[storyteller] Snapshot %s copied to %s."):format(id, dest), vim.log.levels.INFO)
  return { type = "copy", id = id, path = dest }
end

-- List snapshots (git commits or copy dirs).
M.list = function(prj)
  prj = prj or project.current()
  if not prj then
    return {}
  end
  if is_git(prj.root) then
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
  local snapdir = join(prj.build, "snapshots")
  if vim.fn.isdirectory(snapdir) ~= 1 then
    return {}
  end
  return vim.fn.glob(snapdir .. "/*", false, true)
end

return M