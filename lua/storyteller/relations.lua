-- storyteller.relations
-- The relationship graph: parsing `relations:` edges off reference cards,
-- building the node/edge model, deterministic layout, and a character-grid
-- renderer with focus highlighting. Everything here is pure Lua over line
-- arrays so it can be unit-tested headlessly; the reactive view
-- (ui/react_graph.lua) and the classic fallback both render through this.
--
-- Edge syntax on a card (frontmatter), per the standard:
--   relations:
--     - { to: Penelope, kind: spouse }     -- flow map
--     - to: Telemachus                     -- block map
--       kind: parent
--     - spouse: Penelope                   -- shorthand: kind is the key

local project = require("storyteller.project")
local index = require("storyteller.index")

local M = {}

-- --- Parsing ----------------------------------------------------------------

-- Parse one `- value` item from a relations list. Handles flow maps, block
-- maps (to/kind on following, more-indented lines), and the kind:name
-- shorthand. Returns { to, kind } or nil.
local function parse_relation_item(item, following)
  if item:match("^%-%s*%{") then
    local to = item:match("%f[%w]to%s*:%s*([^,%}]+)")
    local kind = item:match("%f[%w]kind%s*:%s*([^,%}]+)")
    if to then
      return { to = vim.trim(to), kind = kind and vim.trim(kind) or "related" }
    end
  end
  local pair_key, pair_value = item:match("^%-+%s*([%w_]+)%s*:%s*(.+)$")
  if pair_key then
    if pair_key == "to" then
      -- Block map: kind may follow on the next, deeper-indented line.
      local kind = "related"
      for _, fl in ipairs(following or {}) do
        local k, v = fl:match("^%s+([%w_]+)%s*:%s*(.+)$")
        if k == "kind" then
          kind = vim.trim(v)
        elseif k then
          break
        end
      end
      return { to = vim.trim(pair_value), kind = kind }
    elseif pair_key ~= "kind" then
      -- Shorthand `- spouse: Penelope`.
      return { to = vim.trim(pair_value), kind = pair_key }
    end
  end
  return nil
end

-- Extract the raw `relations:` frontmatter lines from a card.
local function relations_lines(lines)
  if lines[1] ~= "---" then
    return {}
  end
  local out, in_relations = {}, false
  for i = 2, #lines do
    if lines[i] == "---" then
      break
    end
    if lines[i]:match("^relations:%s*$") then
      in_relations = true
    elseif in_relations then
      if lines[i]:match("^%s") or lines[i]:match("^%-%s") then
        out[#out + 1] = lines[i]
      else
        break
      end
    end
  end
  return out
end

-- Parse relations for one card's lines. Returns { { to, kind }, ... }.
function M.parse_card_relations(lines)
  local raw = relations_lines(lines)
  local out = {}
  local i = 1
  while i <= #raw do
    local ln = raw[i]:gsub("^%s+", "")
    if ln:match("^%-") then
      -- Gather continuation lines (deeper-indented) for block maps.
      local following = {}
      local j = i + 1
      while j <= #raw and raw[j]:match("^%s") and not raw[j]:gsub("^%s+", ""):match("^%-") do
        following[#following + 1] = raw[j]
        j = j + 1
      end
      local rel = parse_relation_item(ln, following)
      if rel then
        out[#out + 1] = rel
      end
      i = j
    else
      i = i + 1
    end
  end
  return out
end

-- --- Graph model -------------------------------------------------------------

-- Build the graph over every reference card in the project:
--   nodes: { name, type, path, mentions, degree }
--   edges: { from, to, kind }   (names resolved to node names when possible)
function M.build(prj)
  prj = prj or project.current()
  local nodes, by_name = {}, {}
  for _, card in ipairs(index.all_references(prj)) do
    local rels = M.parse_card_relations(index.cached_lines(card.path))
    local node = {
      name = card.name,
      type = card.type,
      path = card.path,
      mentions = 0,
      degree = #rels,
    }
    nodes[#nodes + 1] = node
    by_name[card.name:lower()] = node
    node.relations = rels
  end
  -- Mention counts give nodes their visual weight: how often the card's
  -- primary name appears in chapter prose.
  local chapters = index.chapters(prj)
  for _, node in ipairs(nodes) do
    local count = 0
    for _, ch in ipairs(chapters) do
      for _, ln in ipairs(index.cached_lines(ch.path)) do
        local s = 1
        while true do
          local at = ln:find(node.name, s, true)
          if not at then
            break
          end
          count = count + 1
          s = at + #node.name
        end
      end
    end
    node.mentions = count
  end

  local edges = {}
  for _, node in ipairs(nodes) do
    for _, rel in ipairs(node.relations or {}) do
      local target = by_name[rel.to:lower()]
      edges[#edges + 1] = {
        from = node.name,
        to = target and target.name or rel.to,
        kind = rel.kind,
        resolved = target ~= nil,
      }
    end
  end
  table.sort(nodes, function(a, b)
    if a.type ~= b.type then
      return a.type < b.type
    end
    return a.name < b.name
  end)
  table.sort(edges, function(a, b)
    if a.from ~= b.from then
      return a.from < b.from
    end
    return a.kind < b.kind
  end)
  return { nodes = nodes, edges = edges }
end

-- --- Layout ------------------------------------------------------------------

-- Deterministic positions in a normalized [0,1]x[0,1] space. Small casts go
-- on a circle (sorted by name so the layout never shuffles); larger casts are
-- grouped into columns by reference type.
function M.layout(graph, style)
  style = style or {}
  local n = #graph.nodes
  local pos = {}
  if n == 0 then
    return pos
  end
  if n <= (style.circle_max or 14) then
    local cx, cy, r = 0.5, 0.5, 0.38
    for i, node in ipairs(graph.nodes) do
      local angle = (i - 1) * (2 * math.pi / n) - math.pi / 2
      pos[node.name] = {
        x = cx + r * math.cos(angle),
        y = cy + r * 0.62 * math.sin(angle),
      }
    end
  else
    -- Columns by type, types sorted alphabetically, nodes stacked evenly.
    local columns = {}
    for _, node in ipairs(graph.nodes) do
      columns[node.type] = columns[node.type] or {}
      columns[node.type][#columns[node.type] + 1] = node
    end
    local types = {}
    for t in pairs(columns) do
      types[#types + 1] = t
    end
    table.sort(types)
    local col_w = 1 / math.max(1, #types)
    for ci, t in ipairs(types) do
      local members = columns[t]
      for i, node in ipairs(members) do
        pos[node.name] = {
          x = col_w * (ci - 0.5),
          y = (i - 0.5) / #members,
        }
      end
    end
  end
  return pos
end

-- --- Grid rendering ----------------------------------------------------------

local EDGE_CHARS = {
  ["1,0"] = "─",
  ["-1,0"] = "─",
  ["0,1"] = "│",
  ["0,-1"] = "│",
  ["1,1"] = "╲",
  ["1,-1"] = "╱",
  ["-1,1"] = "╱",
  ["-1,-1"] = "╲",
}

-- Bresenham-ish line between grid cells, drawing box-drawing characters into
-- `cells` (a 2D array of chars). Skips one cell short of each endpoint so
-- node boxes survive.
local function draw_edge(cells, w, h, x1, y1, x2, y2)
  local dx = x2 > x1 and 1 or (x2 < x1 and -1 or 0)
  local dy = y2 > y1 and 1 or (y2 < y1 and -1 or 0)
  local x, y = x1, y1
  local guard = (w * h) + 8
  while guard > 0 do
    guard = guard - 1
    if (x == x2 and y == y2) or (math.abs(x - x2) <= 1 and math.abs(y - y2) <= 1) then
      break
    end
    -- Step along the dominant axis for a straighter look.
    local step_x, step_y = 0, 0
    if math.abs(x - x2) >= math.abs(y - y2) and dx ~= 0 then
      step_x = dx
    elseif dy ~= 0 then
      step_y = dy
    else
      step_x = dx
    end
    x, y = x + step_x, y + step_y
    if x >= 1 and x <= w and y >= 1 and y <= h then
      cells[y][x] = EDGE_CHARS[step_x .. "," .. step_y] or "·"
    end
  end
end

---@class RenderOpts
---@field width integer  grid width in cells
---@field height integer grid height in rows
---@field focus string?  focused node name (highlighted)
---@field labels boolean show node labels under boxes (default true)

-- Render the graph into a character grid. Returns:
--   { lines = { { text, hl? }... }, rects = { [name] = {row, col, w, h} } }
-- Each line is a list of runs so views can highlight focused elements.
function M.render_grid(graph, opts)
  opts = opts or {}
  local w = math.max(opts.width or 60, 20)
  local h = math.max(opts.height or 18, 8)
  local labels = opts.labels ~= false
  local pos = M.layout(graph)
  local focus = opts.focus

  local cells = {}
  for y = 1, h do
    cells[y] = {}
    for x = 1, w do
      cells[y][x] = " "
    end
  end

  -- Node boxes: size scales gently with mention weight.
  local half = {}
  for _, node in ipairs(graph.nodes) do
    local weight = math.min(3, math.floor((node.mentions or 0) / 4))
    half[node.name] = 2 + weight
  end

  -- Edges first (under the boxes).
  for _, e in ipairs(graph.edges) do
    local a, b = pos[e.from], pos[e.to]
    if a and b then
      draw_edge(
        cells,
        w,
        h,
        math.floor(a.x * w) + 1,
        math.floor(a.y * h) + 1,
        math.floor(b.x * w) + 1,
        math.floor(b.y * h) + 1
      )
    end
  end

  -- Node markers on top.
  local rects = {}
  for _, node in ipairs(graph.nodes) do
    local p = pos[node.name]
    if p then
      local cx = math.floor(p.x * w) + 1
      local cy = math.floor(p.y * h) + 1
      local r = half[node.name]
      for dy = -1, 1 do
        for dx = -r, r do
          local x, y = cx + dx, cy + dy
          if x >= 1 and x <= w and y >= 1 and y <= h then
            local edge = (math.abs(dy) == 1) or (dx == -r) or (dx == r)
            cells[y][x] = edge and "─" or " "
          end
        end
      end
      -- Label centered under the box.
      if labels then
        local label = node.name
        local start_x = math.max(1, math.min(w - #label + 1, cx - math.floor(#label / 2)))
        for i = 1, #label do
          local x = start_x + i - 1
          if x >= 1 and x <= w and cy + 2 <= h then
            cells[cy + 2][x] = label:sub(i, i)
          end
        end
      end
      rects[node.name] = { row = cy, col = cx - r, w = r * 2 + 1, h = 3 }
    end
  end

  -- Assemble highlighted runs: focused node's rect and its incident edges
  -- get the accent highlight; everything else stays muted.
  local focus_rect = focus and rects[focus] or nil
  local function near_focus(y, x)
    if not focus_rect then
      return false
    end
    if
      y >= focus_rect.row - 1
      and y <= focus_rect.row + focus_rect.h
      and x >= focus_rect.col - 1
      and x <= focus_rect.col + focus_rect.w
    then
      return true
    end
    -- Highlight edges touching the focused node.
    for _, e in ipairs(graph.edges) do
      local a, b = pos[e.from], pos[e.to]
      if a and b and (e.from == focus or e.to == focus) then
        -- cheap proximity test against the segment's bounding box
        local min_x = math.min(a.x, b.x) * w - 1
        local max_x = math.max(a.x, b.x) * w + 1
        local min_y = math.min(a.y, b.y) * h - 1
        local max_y = math.max(a.y, b.y) * h + 1
        if x >= min_x and x <= max_x and y >= min_y and y <= max_y then
          return true
        end
      end
    end
    return false
  end

  local lines = {}
  for y = 1, h do
    local runs = {}
    local current_hl = nil
    local buf = {}
    for x = 1, w do
      local hl = near_focus(y, x) and "StorytellerKey" or "StorytellerDivider"
      if hl ~= current_hl and #buf > 0 then
        runs[#runs + 1] = { text = table.concat(buf), hl = current_hl }
        buf = {}
      end
      current_hl = hl
      buf[#buf + 1] = cells[y][x]
    end
    if #buf > 0 then
      runs[#runs + 1] = { text = table.concat(buf), hl = current_hl }
    end
    lines[#lines + 1] = { segments = runs }
  end
  return { lines = lines, rects = rects }
end

-- --- Edge editing (text-precise, comment/unknown-key preserving) -------------

local function frontmatter_bounds(lines)
  if lines[1] ~= "---" then
    return nil
  end
  for i = 2, #lines do
    if lines[i] == "---" then
      return 2, i - 1
    end
  end
  return nil
end

-- Add `{ to, kind }` to a card's relations block, creating the block when
-- absent. Returns true when the file changed.
function M.add_edge(path, to, kind)
  local lines = vim.fn.readfile(path)
  local out = {}
  local inserted = false
  local rels_at = nil
  for i, ln in ipairs(lines) do
    out[#out + 1] = ln
    if ln:match("^relations:%s*$") then
      rels_at = #out
    end
  end
  local entry = ("  - { to: %s, kind: %s }"):format(to, kind)
  if rels_at then
    table.insert(out, rels_at + 1, entry)
    inserted = true
  else
    local fm_end = frontmatter_bounds(lines)
    if fm_end then
      table.insert(out, fm_end + 1, "relations:")
      table.insert(out, fm_end + 2, entry)
      inserted = true
    end
  end
  if not inserted then
    -- No frontmatter at all: create one.
    local head = { "---", "relations:", entry, "---" }
    out = vim.list_extend(head, lines)
  end
  index.invalidate()
  vim.fn.writefile(out, path)
  return true
end

-- Remove the edge matching `to` (+ optional `kind`) from a card's relations.
function M.remove_edge(path, to, kind)
  local lines = vim.fn.readfile(path)
  local out = {}
  local removed = false
  for _, ln in ipairs(lines) do
    local is_rel_item = ln:match("^%s*-%s*%{") or ln:match("^%s*-%s*[%w_]+%s*:")
    local matches_to = ln:find("to%s*:%s*" .. to, 1, false)
      or ln:find("%f[%w]" .. kind .. "%s*:%s*" .. to)
    if is_rel_item and matches_to and not removed then
      removed = true
    else
      out[#out + 1] = ln
    end
  end
  if removed then
    index.invalidate()
    vim.fn.writefile(out, path)
  end
  return removed
end

return M
