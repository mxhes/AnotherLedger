local ADDON, ns = ...

local floor = math.floor

local Money = {}

-- Splits a copper amount into sign, gold, silver, copper (non-negative ints).
local function split(copper)
  local sign = ""
  if copper < 0 then
    sign = "-"
    copper = -copper
  end
  copper = floor(copper)
  return sign, floor(copper / 10000), floor((copper % 10000) / 100), copper % 100
end

-- Formats a copper amount as "1g 20s 5c", showing only non-zero units.
function Money.format(copper)
  if copper == nil then return "n/a" end
  local sign, g, s, c = split(copper)
  if g == 0 and s == 0 and c == 0 then return "0c" end
  local parts = {}
  if g > 0 then parts[#parts + 1] = g .. "g" end
  if s > 0 then parts[#parts + 1] = s .. "s" end
  if c > 0 then parts[#parts + 1] = c .. "c" end
  return sign .. table.concat(parts, " ")
end

local function hex(c)
  local function byte(v)
    v = tonumber(v) or 0
    if v < 0 then v = 0 elseif v > 1 then v = 1 end
    return floor(v * 255 + 0.5)
  end
  return string.format("|cff%02x%02x%02x", byte(c[1]), byte(c[2]), byte(c[3]))
end

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
  local parts = {}
  if g > 0 then parts[#parts + 1] = hex(colors.moneyGold) .. g .. "g|r" end
  if s > 0 then parts[#parts + 1] = hex(colors.moneySilver) .. s .. "s|r" end
  if c > 0 then parts[#parts + 1] = hex(colors.moneyCopper) .. c .. "c|r" end
  if #parts == 0 then return hex(colors.moneyCopper) .. "0c|r" end
  return sign .. table.concat(parts, " ")
end

ns.Money = Money
