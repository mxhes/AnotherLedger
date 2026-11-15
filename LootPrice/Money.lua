local ADDON, ns = ...

local floor = math.floor

local Money = {}

-- How much of an amount is shown (option "goldDisplay"): "full" = every
-- non-zero unit, "silver" = no copper from 1 gold up, "gold" = gold only from
-- 1 gold up. Amounts under 1 gold always show in full.
local style = "full"

function Money.setStyle(value)
  if value == "silver" or value == "gold" then style = value else style = "full" end
end

-- Splits a copper amount into sign, gold, silver, copper (non-negative ints).
local function split(copper)
  local sign = ""
  if copper < 0 then
    sign = "-"
    copper = -copper
  end
  copper = floor(copper)
  local g, sv, c = floor(copper / 10000), floor((copper % 10000) / 100), copper % 100
  if g > 0 then
    if style == "gold" then sv, c = 0, 0 elseif style == "silver" then c = 0 end
  end
  return sign, g, sv, c
end

-- Appends `piece` to `text` with a space between (text may be nil).
local function join(text, piece)
  if text then return text .. " " .. piece end
  return piece
end

-- Formats a copper amount as "1g 20s 5c", showing only non-zero units.
function Money.format(copper)
  if copper == nil then return "n/a" end
  local sign, g, s, c = split(copper)
  local text
  if g > 0 then text = g .. "g" end
  if s > 0 then text = join(text, s .. "s") end
  if c > 0 then text = join(text, c .. "c") end
  if not text then return "0c" end
  return sign .. text
end

local function byte(v)
  v = tonumber(v) or 0
  if v < 0 then v = 0 elseif v > 1 then v = 1 end
  return floor(v * 255 + 0.5)
end

-- Color escape prefix ("|cffRRGGBB") of a color table, built once per table.
-- Color tables are treated as constants (Theme.colors never change at runtime).
local hexCache = setmetatable({}, { __mode = "k" })
local function hex(color)
  local h = hexCache[color]
  if not h then
    h = string.format("|cff%02x%02x%02x", byte(color[1]), byte(color[2]), byte(color[3]))
    hexCache[color] = h
  end
  return h
end
Money.colorCode = hex

-- Same text as Money.format, each unit's amount and letter wrapped in a color
-- escape ("|cffRRGGBB12g|r"). `colors` = { moneyGold, moneySilver, moneyCopper },
-- each {r, g, b}; defaults to ns.Theme.colors, read at call time (Theme loads
-- after Money). "n/a" and the minus sign stay uncolored, and without any
-- colors the result is the plain text.
function Money.formatColored(copper, colors)
  colors = colors or (ns.Theme and ns.Theme.colors)
  if copper == nil or type(colors) ~= "table"
    or not (colors.moneyGold and colors.moneySilver and colors.moneyCopper) then
    return Money.format(copper)
  end
  local sign, g, s, c = split(copper)
  local text
  if g > 0 then text = hex(colors.moneyGold) .. g .. "g|r" end
  if s > 0 then text = join(text, hex(colors.moneySilver) .. s .. "s|r") end
  if c > 0 then text = join(text, hex(colors.moneyCopper) .. c .. "c|r") end
  if not text then return hex(colors.moneyCopper) .. "0c|r" end
  return sign .. text
end

-- "|cffRRGGBB" escape of a { r, g, b } color (0..1), for colored text.
Money.hex = hex

ns.Money = Money
