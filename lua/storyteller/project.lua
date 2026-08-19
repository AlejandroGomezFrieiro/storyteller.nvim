-- storyteller.project
-- Locates the "project root" for a given file/directory and exposes a
-- normalized `paths` table so the rest of the plugin shares one contract.

local config = require("storyteller.config")
local M = {}

local function join(...)
  return table.concat({ ... }, "/")
end

-- Standard layout mirrors the nixvim_config storytelling template:
--   chapters/, references/{characters,locations,items,organizations}/,
--   outline/, treatment/, research/
local SUBDIRS = {
  "chapters",
  "references/characters",
  "references/locations",
  "references/items",
  "references/organizations",
  "outline",
  "treatment",
  "research",
  "words",
}

-- A "looks like a project" heuristic: chapters/ OR at least one references/.
local function has_layout(root)
  if not root or vim.fn.isdirectory(root) ~= 1 then
    return false
  end
  local has_chapters = vim.fn.isdirectory(join(root, "chapters")) == 1
  local has_ref = vim.fn.isdirectory(join(root, "references")) == 1
  return has_chapters or has_ref
end

-- Find the root directory for `start` (a file path or bufdir). Order:
--   1. an explicit marker file/dir (.storyteller / .storyteller.toml)
--   2. the nearest ancestor that *looks* like a storytelling project,
--      bounded by the enclosing git root (so the project can live anywhere
--      in a real repo, and a repo isn't mistaken for a project)
--   3. the git root itself, if it has the layout
local function find_root_from(start)
  start = start or vim.fn.getcwd()
  -- Normalize: if `start` is a file, resolve to its directory.
  if vim.fn.isdirectory(start) ~= 1 then
    start = vim.fs.dirname(start)
  end

  -- Marker trumps everything: an explicit signal wins.
  for _, marker in ipairs(config.get().markers) do
    local hit = vim.fs.find(marker, { upward = true, path = start })
    if #hit > 0 then
      return vim.fs.dirname(hit[1]), true
    end
  end

  -- Bounding git root (if any).
  local git = vim.fs.find(".git", { upward = true, path = start })
  local gitroot = #git > 0 and vim.fs.dirname(git[1]) or nil

  -- Walk up looking for the layout, stopping at the git root.
  local cur = start
  while cur do
    if has_layout(cur) then
      return cur, false
    end
    if gitroot and cur == gitroot then
      break
    end
    local parent = vim.fs.dirname(cur)
    if parent == cur then
      break
    end
    cur = parent
  end

  -- Fallback: the git root itself (only if it has the layout).
  if gitroot and has_layout(gitroot) then
    return gitroot, false
  end

  return nil
end

-- Absolute path map for a root. Returns nil if not a project.
local function paths_for(root, explicit)
  if not explicit and not has_layout(root) then
    return nil
  end
  return {
    root = root,
    chapters = join(root, "chapters"),
    references = join(root, "references"),
    characters = join(root, "references/characters"),
    locations = join(root, "references/locations"),
    items = join(root, "references/items"),
    organizations = join(root, "references/organizations"),
    outline = join(root, "outline"),
    treatment = join(root, "treatment"),
    research = join(root, "research"),
    words = join(root, "words"),
    build = join(root, "build"),
  }
end

-- --- Public API ------------------------------------------------------------

-- Resolve and cache the project for a path (buffer file or directory).
M.resolve = function(start)
  start = start or vim.fn.expand("%:p")
  if start == "" then
    start = vim.fn.getcwd()
  end
  local root, explicit = find_root_from(start)
  return paths_for(root, explicit)
end

-- Project for the current buffer, if inside one.
M.current = function()
  local bufnr = vim.api.nvim_get_current_buf()
  -- Derived Storyteller buffers (views, Scrivenings) have no filename but
  -- carry their originating project so commands can chain naturally.
  local scrivenings = vim.b[bufnr].storyteller_scrivenings
  if scrivenings and scrivenings.prj then
    return scrivenings.prj
  end
  local attached = vim.b[bufnr].storyteller_project
  if attached then
    return attached
  end
  local file = vim.fn.expand("%:p")
  local candidate = file ~= "" and file or vim.fn.getcwd()
  return M.resolve(candidate)
end

-- Convenience: is the current buffer inside a project?
M.in_project = function()
  return M.current() ~= nil
end

M.paths_for = paths_for
M.join = join
M.SUBDIRS = SUBDIRS

M.setup = function()
  -- no-op; kept for symmetry. Resolution is fully lazy.
end

return M
