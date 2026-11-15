local h = ...
local ns = h.load({ "Util.lua", "Money.lua", "Theme.lua", "History.lua", "Waypoint.lua", "UI/Rows.lua", "UI/DailyFarm.lua", "UI/Compact.lua" })
local DF = ns.UI.DailyFarm

local function farm()
  return {
    best = { zone = "Z", sub = "A", time = 3600, value = 40000, perHour = 40000 },
    runnersUp = { { zone = "Y", sub = "Y", time = 1800, value = 10000, perHour = 20000 } },
  }
end

h.test("DailyFarm.label names the subzone and zone with the rate", function()
  local f = farm()
  local s = DF.label(f)
  h.eq(s:find("A (Z)", 1, true) ~= nil, true)
  h.eq(s:find(ns.Money.format(40000), 1, true) ~= nil, true)
  h.eq(s:find(ns.L["slow selling"], 1, true), nil)
  f.best.sub = "Z"
  h.eq(DF.label(f):find("(Z)", 1, true), nil)
  f.slow = { names = { "Ore" } }
  h.eq(DF.label(f):find(ns.L["slow selling"], 1, true) ~= nil, true)
end)

h.test("DailyFarm.hint lists the place, the runner-ups and the slow sellers", function()
  local f = farm()
  local s = DF.hint(f)
  h.eq(s:find("Z", 1, true) ~= nil, true)
  h.eq(s:find(ns.L["Also good:"], 1, true) ~= nil, true)
  h.eq(s:find("  Y  ", 1, true) ~= nil, true) -- the runner-up is its own zone
  h.eq(s:find("~", 1, true), nil)
  h.eq(s:find(ns.L["Sells slowly: "], 1, true), nil)
  f.slow = { names = { "Ore", "Herb" } }
  f.runnersUp = {}
  s = DF.hint(f)
  h.eq(s:find("Ore, Herb", 1, true) ~= nil, true)
  h.eq(s:find(ns.L["Also good:"], 1, true), nil)
end)

h.test("DailyFarm.label rounds the rate to whole gold from 1 gold up", function()
  local f = farm()
  f.best.perHour = 12345678
  local s = DF.label(f)
  h.eq(s:find(ns.Money.format(12350000), 1, true) ~= nil, true)
  f.best.perHour = 5555 -- under 1 gold: in full
  h.eq(DF.label(f):find(ns.Money.format(5555), 1, true) ~= nil, true)
end)

h.test("DailyFarm.hint lists the clicks: waypoint ones only with a spot", function()
  local f = farm()
  local s = DF.hint(f)
  h.eq(s:find(ns.L["Click to open it in Zones"], 1, true) ~= nil, true)
  h.eq(s:find(ns.L["Click: waypoint"], 1, true), nil)
  f.best.pos = { mapID = 1, x = 0.5, y = 0.5 }
  s = DF.hint(f)
  h.eq(s:find(ns.L["Click: waypoint"], 1, true) ~= nil, true)
  h.eq(s:find(ns.L["Shift-click: open it in Zones"], 1, true) ~= nil, true)
  h.eq(s:find(ns.L["Right-click: copy the /way line"], 1, true) ~= nil, true)
  h.eq(s:find(ns.L["Click to open it in Zones"], 1, true), nil)
end)

h.test("DailyFarm.label puts the rate first so a narrow window cuts the place", function()
  local f = farm()
  local s = DF.label(f)
  -- Short prefix and no tilde (it sits raised in the game font).
  h.eq(s:sub(1, #ns.L["Daily: "]), ns.L["Daily: "])
  h.eq(s:find("~", 1, true), nil)
  h.eq(s:find(ns.L["/h"], 1, true) < s:find("A (Z)", 1, true), true)
  f.slow = { names = { "Ore" } }
  local slow = DF.label(f)
  h.eq(slow:find(ns.L["slow selling"], 1, true) > slow:find("A (Z)", 1, true), true)
end)

h.test("Compact fits its body at the minimum window height", function()
  local C = ns.UI.Compact
  h.eq(C ~= nil, true)
  local S = ns.Theme.sizes
  h.eq(S.compactMinHeight >= C.requiredHeight(), true)
  h.eq(S.compactHeight >= S.compactMinHeight, true)
end)
