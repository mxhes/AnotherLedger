local ADDON, ns = ...

-- Small helpers shared by every module. Loaded first; pure except `say`.
local Util = {}

local huge = math.huge
local floor = math.floor

-- A real, finite number (saved variables and addon APIs can hand back anything).
function Util.isNumber(v)
  return type(v) == "number" and v == v and v ~= huge and v ~= -huge
end

local isNumber = Util.isNumber

function Util.isPositive(v)
  return isNumber(v) and v > 0
end

function Util.isPositiveInt(v)
  return isNumber(v) and v > 0 and v == floor(v)
end

-- `v` when it is a number >= 0, else 0.
function Util.nonNegative(v)
  return isNumber(v) and v >= 0 and v or 0
end

function Util.clamp(v, lo, hi)
  if hi < lo then hi = lo end
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

-- Age in its largest whole unit: "3d", "5h", "12m" (never below "1m").
function Util.shortAge(seconds)
  if seconds >= 86400 then return floor(seconds / 86400) .. "d" end
  if seconds >= 3600 then return floor(seconds / 3600) .. "h" end
  return math.max(1, floor(seconds / 60)) .. "m"
end

-- The saved value of option `key` (Options.get), or `fallback` before the
-- saved variables are loaded or without the option registry (some tests).
function Util.setting(key, fallback)
  local O = ns.Options
  if not (O and ns.db) then return fallback end
  local v = O.get(ns.db, key)
  if v == nil then return fallback end
  return v
end

-- Option "rawGold": whether looted raw gold counts in the totals, and whether
-- the footer table shows its own Raw gold row. Returns counted, row.
local RAW_GOLD = { row = { true, true }, total = { true, false }, apart = { false, true }, off = { false, false } }
function Util.rawGold()
  local mode = RAW_GOLD[Util.setting("rawGold", "row")] or RAW_GOLD.row
  return mode[1], mode[2]
end

-- Whether raw gold counts in the totals (option "rawGold").
function Util.goldCounted()
  return (Util.rawGold())
end

local PREFIX = "|cff33ff99LootLedger|r: "

-- Chat line with the addon prefix.
function Util.say(msg)
  print(PREFIX .. msg)
end

ns.Util = Util
