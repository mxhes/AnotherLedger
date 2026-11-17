local ADDON, ns = ...

ns.UI = ns.UI or {}

-- Amounts in coin columns, like the game's own money displays: gold, silver
-- and copper each right-aligned in its own column, so every coin of a kind
-- lines up down a list (rows, compact drops, footer, Top finds). A cell is a
-- frame with one FontString per unit (Money.parts) and one for a plain text
-- (an em dash, "bound", "?"). The cells of one column are laid out together
-- (Coins.align): each unit column is as wide as its widest part among them,
-- a column no cell uses takes no room. Short parts also keep the error of an
-- outlined font (it grows with the text) to a pixel or so.
-- The helpers up to "Widgets" are pure; the rest is client-only and touches
-- WoW globals inside functions only.
local Coins = {}
ns.UI.Coins = Coins

Coins.UNITS = { "gold", "silver", "copper" }

-- Right edge of each unit column, measured leftwards from the cell's right
-- edge, and the width of all columns. `widths` = { gold, silver, copper }
-- (0 or nil: no such column); `gap` between two columns.
function Coins.columns(widths, gap)
  local right, x, any = {}, 0, false
  for i = #Coins.UNITS, 1, -1 do
    local u = Coins.UNITS[i]
    local w = widths[u] or 0
    if w > 0 then
      if any then x = x + gap end
      right[u] = x
      x = x + w
      any = true
    else
      right[u] = x
    end
  end
  return right, x
end

-- The widths of a group of cells: per unit the widest part, and the widest
-- plain text. `naturals` = list of { gold, silver, copper, text } widths.
function Coins.groupWidths(naturals)
  local w = { gold = 0, silver = 0, copper = 0, text = 0 }
  for _, n in ipairs(naturals) do
    for k, best in pairs(w) do
      local v = n[k]
      if type(v) == "number" and v > best then w[k] = v end
    end
  end
  return w
end

-- Width of a group: its columns, or its widest plain text when that is wider.
function Coins.groupWidth(widths, gap)
  local _, total = Coins.columns(widths, gap)
  return math.max(total, widths.text or 0)
end

-- ---------------------------------------------------------------------------
-- Widgets

local function positive(v) return type(v) == "number" and v > 0 end

-- A new cell in `font` and `color` (a theme color, recolored live).
function Coins.new(parent, font, color)
  local W = ns.UI.Widgets
  local cell = CreateFrame("Frame", nil, parent)
  cell.parts, cell.has = {}, {}
  for _, u in ipairs(Coins.UNITS) do
    cell.parts[u] = W.text(cell, font, color, "RIGHT")
    cell.has[u] = false
  end
  cell.text = W.text(cell, font, color, "RIGHT")
  cell.text:SetPoint("RIGHT", cell, "RIGHT", 0, 0)
  cell.hasText = false
  cell.full = ""
  cell.layoutKey = false
  -- The whole amount as one text (what a single FontString used to show).
  cell.GetText = function(self) return self.full end
  return cell
end

-- Shows `copper` (an amount) in the coin columns, or `text` when copper is
-- nil.
function Coins.set(cell, copper, text)
  local parts = copper ~= nil and ns.Money.parts(copper, ns.Theme.colors) or nil
  local full = {}
  for _, u in ipairs(Coins.UNITS) do
    local s = parts and parts[u] or ""
    cell.parts[u]:SetText(s)
    cell.has[u] = s ~= ""
    if s ~= "" then full[#full + 1] = s end
  end
  local t = parts and "" or (text or "")
  cell.text:SetText(t)
  cell.hasText = t ~= ""
  cell.full = parts and table.concat(full, " ") or t
end

-- Empties the cell, so the next Set measures its texts again (a FontString
-- given the same text may keep the width of an older font).
function Coins.clear(cell)
  for _, u in ipairs(Coins.UNITS) do cell.parts[u]:SetText("") end
  cell.text:SetText("")
end

-- The widths of the cell's parts and text (0 for empty ones).
function Coins.natural(cell)
  local n = {}
  for _, u in ipairs(Coins.UNITS) do
    local w = cell.has[u] and cell.parts[u]:GetStringWidth() or 0
    n[u] = positive(w) and w or 0
  end
  local w = cell.hasText and cell.text:GetStringWidth() or 0
  n.text = positive(w) and w or 0
  return n
end

-- Height of the cell's line: its tallest text (fallback Theme coinHeight).
local function lineHeight(cell)
  local best = 0
  for _, fs in pairs(cell.parts) do
    local h = fs:GetStringHeight()
    if positive(h) and h > best then best = h end
  end
  local h = cell.text:GetStringHeight()
  if positive(h) and h > best then best = h end
  return best > 0 and best or ns.Theme.sizes.coinHeight
end

-- Places the cell's parts in the group's columns and sizes the cell.
function Coins.layout(cell, widths, gap)
  local right = Coins.columns(widths, gap)
  local key = right.gold .. ":" .. right.silver .. ":" .. right.copper
  if cell.layoutKey ~= key then
    cell.layoutKey = key
    for _, u in ipairs(Coins.UNITS) do
      local fs = cell.parts[u]
      fs:ClearAllPoints()
      fs:SetPoint("RIGHT", cell, "RIGHT", -right[u], 0)
    end
  end
  cell:SetSize(math.max(1, Coins.groupWidth(widths, gap)), lineHeight(cell))
end

-- Lays out the shown cells of one column together. Returns the column's
-- width (0 without a shown cell).
function Coins.align(cells, gap)
  gap = gap or ns.Theme.sizes.coinGap
  local naturals, shown = {}, {}
  for _, cell in ipairs(cells) do
    if cell:IsShown() then
      shown[#shown + 1] = cell
      naturals[#naturals + 1] = Coins.natural(cell)
    end
  end
  if #shown == 0 then return 0 end
  local widths = Coins.groupWidths(naturals)
  for _, cell in ipairs(shown) do Coins.layout(cell, widths, gap) end
  return Coins.groupWidth(widths, gap)
end
