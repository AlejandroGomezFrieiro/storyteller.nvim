-- luacheck config for storyteller.nvim
std = "luajit"
globals = { "vim" }
max_line_length = 100

exclude_files = {}

-- Project-wide relaxations:
--   431 shadowing upvalue — repeated pcall(ok, ...) locals
--   213 unused loop variable — conventional `_i`/`_j` placeholders
--   311 value assigned but unused — deliberate reassignments before use
--   421 shadowing local — iterative parsers reuse short names (coord, t, …)
ignore = { "431", "213", "311", "421" }

files["lua/storyteller/commands.lua"] = {
  -- Every handler shares the (prj, args, opts) signature; not all use all three.
  ignore = { "212" },
}
files["lua/storyteller/capture.lua"] = {
  ignore = { "212" },
}

files["tests/**"] = {
  -- Tests intentionally monkey-patch os.date and reuse short loop names.
  ignore = { "122", "shadowing", "211", "212", "221", "231" },
}
