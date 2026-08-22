-- storyteller.config
-- User-facing defaults and option resolution. `setup(opts)` merges opts on top.

local M = {}

local DEFAULTS = {
  -- How the project root is detected (in order of preference).
  markers = { ".storyteller", ".storyteller.toml" },
  -- Optional user override dir for story-structure templates (`templates_dir/`).
  templates_dir = nil,
  -- Whether autocmds auto-run for markdown files inside a project.
  autocmds = true,
  -- Detection: auto-run reference detection on save for the current scene.
  detect_on_save = true,
  detect_debounce = 300, -- ms
  -- Where file-backed annotations live (relative to the project root).
  notes_file = "notes/annotations.md",
  -- Picker backend: "telescope" | "fzf" | "auto".
  picker = "auto",
  -- The TUI binary for `:Story tui` (probed on first use; override to pin).
  tui_bin = "storyteller-tui",
  -- Theme passthrough for the TUI: "dark" | "light" | "midnight" | "forest"
  -- | "contrast". nil lets the TUI auto-detect.
  tui_theme = nil,
  -- Glyph tier: "safe" (default) or "nerd" once nerd tables ship.
  tui_glyphs = nil,
  -- Prefer the embedded TUI cockpit as the dashboard overview: `:Story`
  -- launches the terminal cockpit instead of the buffer dashboard when the
  -- `storyteller-tui` binary is available. The buffer dashboard stays
  -- reachable via `:Story dashboard`. Defaults to false (buffer dashboard).
  tui_first = false,
  -- Heatmap window width in weeks for the tracking dashboard.
  heatmap_weeks = 30,
  -- Binaries (optional). Probed lazily on first use; override to pin a path.
  rg = nil,
  pandoc = nil,
  status = {
    show_session = true,
    show_target = true,
  },
}

M.defaults = function()
  return vim.deepcopy(DEFAULTS)
end

M.setup = function(opts)
  opts = opts or {}
  M.user = vim.tbl_deep_extend("force", M.user or M.defaults(), opts)
  return M.user
end

M.get = function()
  if not M.user then
    M.setup()
  end
  return M.user
end

-- Lazy binary probe: resolved on first use so environment changes after
-- startup (PATH changes, nix shells) are honored. An explicit config value
-- always wins.
M.bin = function(name)
  local cfg = M.get()
  if cfg[name] ~= nil then
    return cfg[name] or nil
  end
  if vim.fn.executable(name) == 1 then
    return name
  end
  return nil
end

return M
