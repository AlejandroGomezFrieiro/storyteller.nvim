-- storyteller.references
-- Reference detection and browsing UI.
--
--   references.suggest(sc, prj)  run detection and present per-suggestion
--                                actions (link / dismiss / link-all).
--   references.panel(prj)        pick any reference card grouped by type,
--                                opening the card file on select.

local project = require("storyteller.project")
local index = require("storyteller.index")
local detect = require("storyteller.detect")
local pickers = require("storyteller.pickers")

local M = {}

-- Ask the user which action to take for a single suggestion.
local function ask_action(scene, sug, prj)
  vim.ui.select({ "link", "dismiss", "link all" }, {
    prompt = ("[%d%%] %s (%s)"):format(math.floor(sug.confidence * 100 + 0.5), sug.name, sug.type),
  }, function(choice)
    if choice == "link" then
      detect.link(scene, sug.reference)
      vim.notify(("[storyteller] Linked %s (%s)."):format(sug.name, sug.type), vim.log.levels.INFO)
    elseif choice == "dismiss" then
      detect.dismiss(scene, sug.reference.name)
      vim.notify(("[storyteller] Dismissed %s."):format(sug.reference.name), vim.log.levels.INFO)
    elseif choice == "link all" then
      local n = detect.link_all(scene, prj)
      vim.notify(("[storyteller] Auto-linked %s confident reference(s)."):format(n), vim.log.levels.INFO)
    end
  end)
end

-- Present detections for the current scene via the picker.
M.suggest = function(sc, prj)
  prj = prj or project.current()
  if not prj then
    return
  end
  local sugs = detect.detect_scene(sc, prj)
  if #sugs == 0 then
    vim.notify("[storyteller] No new references detected in this scene.", vim.log.levels.INFO)
    return
  end
  local entries = {}
  for _, s in ipairs(sugs) do
    local pct = ("%d%%"):format(math.floor(s.confidence * 100 + 0.5))
    table.insert(entries, {
      value = { scene = sc, sug = s },
      display = ("[%5s] %-28s (%s)"):format(pct, s.name, s.type),
    })
  end
  pickers.pick_list(entries, {
    prompt_title = "Storyteller detection",
    on_select = function(value, _action)
      if value and value.scene then
        ask_action(value.scene, value.sug, prj)
      end
    end,
  })
end

-- Browse all reference cards grouped by type.
M.panel = function(prj)
  prj = prj or project.current()
  if not prj then
    return
  end
  local refs = index.references(prj)
  local groups = {
    { key = "characters", label = "Characters" },
    { key = "locations", label = "Locations" },
    { key = "items", label = "Items" },
    { key = "organizations", label = "Organizations" },
  }
  local entries = {}
  for _, g in ipairs(groups) do
    local cards = refs[g.key] or {}
    if #cards > 0 then
      table.insert(entries, {
        value = nil,
        display = ("▸ %s (%d)"):format(g.label, #cards),
      })
      for _, c in ipairs(cards) do
        table.insert(entries, {
          value = c,
          display = ("  %s"):format(c.title or c.path),
        })
      end
    end
  end
  if #entries == 0 then
    vim.notify("[storyteller] No reference cards found.", vim.log.levels.WARN)
    return
  end
  pickers.pick_list(entries, {
    prompt_title = "Storyteller references",
    on_select = function(card, _action)
      if card and card.path then
        vim.cmd("edit " .. vim.fn.fnameescape(card.path))
      end
    end,
  })
end

return M
