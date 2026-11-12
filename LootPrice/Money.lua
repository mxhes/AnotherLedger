local ADDON, ns = ...

local floor = math.floor

local Money = {}

-- Formats a copper amount as "1g 20s 5c", showing only non-zero units.
function Money.format(copper)
  if copper == nil then return "n/a" end
  local sign = ""
  if copper < 0 then
    sign = "-"
    copper = -copper
  end
  copper = floor(copper)
  if copper == 0 then return "0c" end
  local g = floor(copper / 10000)
  local s = floor((copper % 10000) / 100)
  local c = copper % 100
  local parts = {}
  if g > 0 then parts[#parts + 1] = g .. "g" end
  if s > 0 then parts[#parts + 1] = s .. "s" end
  if c > 0 then parts[#parts + 1] = c .. "c" end
  return sign .. table.concat(parts, " ")
end

ns.Money = Money
