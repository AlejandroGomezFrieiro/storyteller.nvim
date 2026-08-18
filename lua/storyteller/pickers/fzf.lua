-- storyteller.pickers.fzf
-- fzf-lua-backed pickers (used when fzf-lua is available and chosen).

local M = {}

local function fzf()
  local ok, mod = pcall(require, "fzf-lua")
  return ok and mod or nil
end

M.pick = function(kind, opts)
  opts = opts or {}
  local f = fzf()
  if not f then
    return
  end
  if kind == "files" then
    f.files({ cwd = opts.cwd, prompt = opts.prompt_title or "Storyteller files> " })
  elseif kind == "grep" then
    f.grep({ cwd = opts.cwd, search = opts.search or "", prompt = opts.prompt_title or "Storyteller grep> " })
  elseif kind == "buffers" then
    f.buffers({ prompt = opts.prompt_title or "Buffers> " })
  end
end

M.pick_list = function(entries, opts)
  opts = opts or {}
  local f = fzf()
  if not f then
    return
  end
  local lines, valmap = {}, {}
  for _, e in ipairs(entries) do
    local display = e.display or tostring(e.value)
    lines[#lines + 1] = display
    valmap[display] = e.value
  end
  f.fzf_exec(lines, {
    prompt = opts.prompt_title or "Storyteller> ",
    actions = {
      ["default"] = function(selected)
        local val = valmap[selected[1]]
        if val and opts.on_select then
          opts.on_select(val, "default")
        end
      end,
    },
  })
end

return M