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

-- A rate for a short text: whole gold from 1 gold up (the hover text has the
-- exact amount), whole copper below.
function Money.roundRate(copper)
  if copper >= 10000 then return floor(copper / 10000 + 0.5) * 10000 end
  return floor(copper + 0.5)
end

-- Option "coinIcons": the game's coin icons (inline textures, as tall as the
-- text) in place of the g / s / c letters. Off until Options.applyAll.
Money.ICONS = {
  gold = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t",
  silver = "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t",
  copper = "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t",
}
local LETTERS = { gold = "g", silver = "s", copper = "c" }
local unit = LETTERS

function Money.setIcons(on)
  unit = on and Money.ICONS or LETTERS
end

function Money.iconsOn() return unit == Money.ICONS end

-- Appends `piece` to `text` with a space between (text may be nil).
local function join(text, piece)
  if text then return text .. " " .. piece end
  return piece
end

-- Formats a copper amount as "1g 20s 5c" (or with coin icons), showing only
-- non-zero units.
function Money.format(copper)
  if copper == nil then return "n/a" end
  local sign, g, s, c = split(copper)
  local text
  if g > 0 then text = g .. unit.gold end
  if s > 0 then text = join(text, s .. unit.silver) end
  if c > 0 then text = join(text, c .. unit.copper) end
  if not text then return "0" .. unit.copper end
  return sign .. text
end

local function byte(v)
  v = tonumber(v) or 0
  if v < 0 then v = 0 elseif v > 1 then v = 1 end
  return floor(v * 255 + 0.5)
end

-- Color escape prefix ("|cffRRGGBB") of a color table. Cached by the color's
-- value, not the table: the color options change Theme.colors in place
-- (Theme.setColor), and the text must follow at once.
local hexCache = {}
local function hex(color)
  local r, g, b = byte(color[1]), byte(color[2]), byte(color[3])
  local key = (r * 256 + g) * 256 + b
  local h = hexCache[key]
  if not h then
    h = string.format("|cff%02x%02x%02x", r, g, b)
    hexCache[key] = h
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
  if g > 0 then text = hex(colors.moneyGold) .. g .. unit.gold .. "|r" end
  if s > 0 then text = join(text, hex(colors.moneySilver) .. s .. unit.silver .. "|r") end
  if c > 0 then text = join(text, hex(colors.moneyCopper) .. c .. unit.copper .. "|r") end
  if not text then return hex(colors.moneyCopper) .. "0" .. unit.copper .. "|r" end
  return sign .. text
end

-- The units of an amount for coin columns (UI/Coins.lua): { gold, silver,
-- copper }, each that unit's number with its coin or letter (colored like
-- formatColored when `colors` has the money colors), nil when the unit is not
-- shown. Same units as Money.format; zero is copper "0"; the minus sign goes
-- before the first unit. nil for a nil amount.
function Money.parts(copper, colors)
  if copper == nil then return nil end
  local colored = type(colors) == "table" and colors.moneyGold and colors.moneySilver and colors.moneyCopper
  local function piece(n, key, colorKey)
    local text = n .. unit[key]
    if colored then return hex(colors[colorKey]) .. text .. "|r" end
    return text
  end
  local sign, g, s, c = split(copper)
  local out = {}
  if g > 0 then out.gold = piece(g, "gold", "moneyGold") end
  if s > 0 then out.silver = piece(s, "silver", "moneySilver") end
  if c > 0 or not (out.gold or out.silver) then out.copper = piece(c, "copper", "moneyCopper") end
  if sign ~= "" then
    local first = out.gold and "gold" or out.silver and "silver" or "copper"
    out[first] = sign .. out[first]
  end
  return out
end

ns.Money = Money
