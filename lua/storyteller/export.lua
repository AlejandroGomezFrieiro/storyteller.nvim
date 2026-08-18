-- storyteller.export
-- Export a project to manuscript formats via pandoc (optional binary).
-- Formats: docx, epub, pdf, smf (Standard Manuscript Format, docx +
-- `--reference-doc`). Outputs land under `prj.build/`. When pandoc is
-- unavailable the caller is notified instead of raising an error.

local config = require("storyteller.config")
local project = require("storyteller.project")
local index = require("storyteller.index")

local M = {}

local VALID = { docx = true, epub = true, pdf = true, smf = true }

local function join(...)
  return table.concat({ ... }, "/")
end

-- Reference doc for SMF export, resolved from a `templates/storyteller/`
-- override or the plugin package. Returns a path or nil.
local function reference_doc()
  local candidates = {}
  local function add(p)
    if p and p ~= "" then
      table.insert(candidates, p)
    end
  end
  add(join(vim.fn.getcwd(), "templates/storyteller/reference.docx"))
  for _, base in ipairs(vim.opt.runtimepath:get() or {}) do
    if base ~= "" then
      add(join(base, "templates/storyteller/reference.docx"))
      add(join(base, "reference.docx"))
    end
  end
  for _, p in ipairs(candidates) do
    if vim.loop.fs_stat(p) then
      return p
    end
  end
  return nil
end

local function have_pandoc()
  return vim.fn.executable("pandoc") == 1
end

local function run_pandoc(args)
  local parts = { "pandoc" }
  for _, a in ipairs(args) do
    table.insert(parts, a)
  end
  vim.fn.system(parts)
  return vim.v.shell_error == 0
end

-- Validate a format string; notify + return normalized fmt (default "docx")
-- or nil when unknown.
local function check_fmt(fmt)
  if not fmt or fmt == "" then
    fmt = "docx"
  end
  fmt = fmt:lower()
  if not VALID[fmt] then
    vim.notify(
      ("[storyteller] Unknown export format '%s' (docx, epub, pdf, smf)"):format(tostring(fmt)),
      vim.log.levels.ERROR
    )
    return nil
  end
  return fmt
end

local function require_prj(prj)
  prj = prj or project.current()
  if not prj then
    vim.notify("[storyteller] Not in a storytelling project.", vim.log.levels.WARN)
    return nil
  end
  return prj
end

local function filestem(path)
  return vim.fn.fnamemodify(path, ":t:r")
end

-- --- Public API -------------------------------------------------------------

-- Export a single markdown file. Returns the output path or nil.
M.file = function(prj, file, fmt)
  fmt = check_fmt(fmt)
  if not fmt then
    return nil
  end
  prj = require_prj(prj)
  if not prj then
    return nil
  end
  if not have_pandoc() then
    vim.notify("[storyteller] pandoc not found; install pandoc to export.", vim.log.levels.ERROR)
    return nil
  end
  vim.fn.mkdir(prj.build, "p")
  local target = fmt == "smf" and "docx" or fmt
  local base = filestem(file)
  local out = join(prj.build, base .. "." .. target)
  local args = {
    tostring(file),
    "--to=" .. tostring(target),
    "--output=" .. tostring(out),
  }
  if fmt == "smf" then
    local ref = reference_doc()
    if ref then
      table.insert(args, "--reference-doc=" .. ref)
    else
      vim.notify("[storyteller] No reference.docx found; exporting smf without a reference doc.", vim.log.levels.WARN)
    end
  end
  local ok = run_pandoc(args)
  if not ok then
    vim.notify(("[storyteller] pandoc failed."):format(), vim.log.levels.ERROR)
    return nil
  end
  return out
end

-- Stitch chapters into `build/manuscript.md`, then export. Returns output path.
M.export_manuscript = function(prj, fmt)
  fmt = check_fmt(fmt)
  if not fmt then
    return nil
  end
  prj = require_prj(prj)
  if not prj then
    return nil
  end
  if not have_pandoc() then
    vim.notify("[storyteller] pandoc not found; manuscript export unavailable.", vim.log.levels.ERROR)
    return nil
  end
  vim.fn.mkdir(prj.build, "p")
  local target = fmt == "smf" and "docx" or fmt
  local ms = join(prj.build, "manuscript.md")
  local out_lines = {}
  for _, ch in ipairs(index.chapters(prj)) do
    vim.list_extend(out_lines, vim.fn.readfile(ch.path))
    table.insert(out_lines, "")
    table.insert(out_lines, "")
  end
  vim.fn.writefile(out_lines, ms)
  local out = join(prj.build, "manuscript." .. target)
  local args = {
    ms,
    "--to=" .. tostring(target),
    "--output=" .. tostring(out),
  }
  if fmt == "smf" then
    local ref = reference_doc()
    if ref then
      table.insert(args, "--reference-doc=" .. ref)
    else
      vim.notify("[storyteller] No reference.docx found; smf exported without a reference doc.", vim.log.levels.WARN)
    end
  end
  local ok = run_pandoc(args)
  if not ok then
    vim.notify(("[storyteller] pandoc failed."):format(), vim.log.levels.ERROR)
    return nil
  end
  return out
end

-- Spec'd alias: export(prj, file, fmt) → single-file export.
M.export = M.file
-- Whole-project (manuscript) export entrypoints.
M.project = M.export_manuscript
M.export_project = M.export_manuscript
M.manuscript = M.export_manuscript

return M